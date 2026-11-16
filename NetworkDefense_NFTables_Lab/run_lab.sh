#!/usr/bin/env bash
# Safe, isolated Network Defense lab with kernel nftables. No public network endpoints.
set -Eeuo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"
REPEATS="${REPEATS:-5}"
CYCLES="${CYCLES:-3}"
MODE_ARGS="${1:-}"

if [[ "$MODE_ARGS" != "--inside" ]]; then
  for program in ip python3 unshare; do
    command -v "$program" >/dev/null || { echo "Missing dependency: $program" >&2; exit 2; }
  done
  if [[ "$MODE_ARGS" != "--smoke-only" ]] && ! command -v nft >/dev/null; then
    echo "nft not available. On your dedicated Ubuntu VM: sudo apt update && sudo apt install nftables iproute2 python3 util-linux" >&2
    exit 2
  fi
  if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash run_lab.sh (only in a dedicated VM)" >&2
    exit 2
  fi
  # Full namespace isolation. No silent fallback to production network namespace.
  export ND_SMOKE=0
  [[ "$MODE_ARGS" == "--smoke-only" ]] && export ND_SMOKE=1
  if [[ "$MODE_ARGS" == "--vm-root" ]]; then
    # Intended only for an ephemeral, dedicated VM, such as a GitHub-hosted full VM.
    # Still isolates mount+network namespaces, but uses root's real capabilities.
    echo "VM-root mode: creating new mount and network namespaces (no host networking changed)."
    exec unshare -mn -- bash "$BASE/run_lab.sh" --inside
  fi
  echo "Isolating all virtual networks in a new user, mount and network namespace..."
  exec unshare -Urnm -- bash "$BASE/run_lab.sh" --inside
fi

mkdir -p results
rm -f results/tcp_*.csv results/pivot_*.csv results/marker_outcomes.txt results/markers_*.jsonl results/ruleset_* results/summary.json
printf 'timestamp=%s\nkernel=%s\npython=%s\niproute2=%s\n' "$(date -u +%FT%TZ)" "$(uname -r)" "$(python3 --version)" "$(ip -V)" > results/environment.txt
if [[ "${ND_SMOKE:-0}" != 1 ]]; then
  nft --version >> results/environment.txt
fi

HOSTS=(attacker user web database admin)
declare -A IP
PIDS=()
NS_ALL=(ndlab-fw ndlab-attacker ndlab-user ndlab-web ndlab-database ndlab-admin)
cleanup() {
  set +e
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null; done
  wait 2>/dev/null
  PIDS=()
  for ns in "${NS_ALL[@]}"; do
    if ip netns list | grep -q "^$ns\b"; then
      for p in $(ip netns pids "$ns"); do kill "$p" 2>/dev/null; done
      ip netns del "$ns" 2>/dev/null
    fi
  done
}
trap cleanup EXIT

make_topology() {
  local mode="$1"
  for ns in "${NS_ALL[@]}"; do ip netns add "$ns"; ip -n "$ns" link set lo up; done
  local i=1 h
  for h in "${HOSTS[@]}"; do
    ip link add "h-$h" type veth peer name "r-$h"
    ip link set "h-$h" netns "ndlab-$h"
    ip link set "r-$h" netns ndlab-fw
    ip -n "ndlab-$h" link set "h-$h" up
    ip -n ndlab-fw link set "r-$h" up
    if [[ "$mode" == flat ]]; then
      IP[$h]="10.99.0.$((10*i))"
      ip -n "ndlab-$h" addr add "${IP[$h]}/24" dev "h-$h"
    else
      IP[$h]="10.99.$i.10"
      ip -n "ndlab-$h" addr add "${IP[$h]}/24" dev "h-$h"
      ip -n ndlab-fw addr add "10.99.$i.1/24" dev "r-$h"
      ip -n "ndlab-$h" route add default via "10.99.$i.1"
    fi
    i=$((i+1))
  done
  if [[ "$mode" == flat ]]; then
    ip -n ndlab-fw link add br-flat type bridge
    ip -n ndlab-fw link set br-flat up
    for h in "${HOSTS[@]}"; do ip -n ndlab-fw link set "r-$h" master br-flat; done
  else
    # A routed test is invalid unless kernel forwarding is actually enabled.
    if ! ip netns exec ndlab-fw sysctl -q -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
      echo "STOP: cannot enable net.ipv4.ip_forward in the isolated router namespace." >&2
      echo "This environment cannot produce valid routed/ACL evidence. Use a dedicated Ubuntu VM." >&2
      exit 4
    fi
    if [[ "$(ip netns exec ndlab-fw sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
      echo "STOP: IPv4 forwarding remains disabled; aborting rather than reporting false firewall blocks." >&2
      exit 4
    fi
    if [[ "$mode" == routed_open ]] && [[ "${ND_SMOKE:-0}" != 1 ]]; then
      cat > "results/open_policy.nft" <<'EOF'
table inet ndlab {
  chain forward {
    type filter hook forward priority filter; policy accept;
    counter accept
  }
}
EOF
      ip netns exec ndlab-fw nft -f results/open_policy.nft
    elif [[ "$mode" == segmented_acl ]]; then
      cat > "results/segmented_policy.nft" <<'EOF'
table inet ndlab {
  chain forward {
    type filter hook forward priority filter; policy drop;
    ct state established,related counter accept
    iifname "r-attacker" oifname "r-user" tcp dport 8080 counter accept
    iifname "r-attacker" oifname "r-web" tcp dport 8080 counter accept
    iifname "r-web" oifname "r-database" tcp dport 8080 counter accept
    counter reject with icmpx type admin-prohibited
  }
}
EOF
      ip netns exec ndlab-fw nft -f results/segmented_policy.nft
    fi
  fi
}

start_services() {
  local cycle="$1" mode="$2" h
  for h in user web database admin; do
    ip netns exec "ndlab-$h" python3 -u "$BASE/service.py" --name "$h" --ip "${IP[$h]}" \
      --database-ip "${IP[database]}" --marker-log "$BASE/results/markers_${mode}_c${cycle}.jsonl" \
      >"results/server_${mode}_${h}_c${cycle}.log" 2>&1 &
    PIDS+=("$!")
  done
  sleep 0.4
  for pid in "${PIDS[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "A lab server failed; check results/server logs" >&2; exit 3
    fi
  done
}

probe_all() {
  local cycle="$1" mode="$2" ip_json
  ip_json="$(python3 -c 'import json,sys; print(json.dumps(dict(x.split("=") for x in sys.argv[1:])))' \
    "user=${IP[user]}" "web=${IP[web]}" "database=${IP[database]}" "admin=${IP[admin]}")"
  ip netns exec ndlab-attacker python3 "$BASE/probe.py" \
    --mode "$mode" --cycle "$cycle" --source attacker --target-map-json "$ip_json" \
    --output "$BASE/results/tcp_${mode}_c${cycle}.csv" --repeats "$REPEATS"
  ip netns exec ndlab-web python3 "$BASE/probe.py" \
    --mode "$mode" --cycle "$cycle" --source web --target-map-json "{\"database\":\"${IP[database]}\"}" \
    --output "$BASE/results/pivot_${mode}_c${cycle}.csv" --repeats "$REPEATS"
  local marker="CONTROLLED_MARKER_${mode}_c${cycle}" result
  result="$(ip netns exec ndlab-attacker python3 -c 'import socket,sys; s=socket.create_connection((sys.argv[1],8080),1); s.sendall(("TRIGGER "+sys.argv[2]+"\n").encode()); print(s.recv(256).decode().strip()); s.close()' "${IP[web]}" "$marker")"
  printf 'mode=%s cycle=%s marker=%s result=%s\n' "$mode" "$cycle" "$marker" "$result" | tee -a results/marker_outcomes.txt
  if [[ "$mode" != flat ]] && [[ "${ND_SMOKE:-0}" != 1 ]]; then
    ip netns exec ndlab-fw nft -a list ruleset >"results/ruleset_${mode}_c${cycle}.txt"
    ip netns exec ndlab-fw nft -j list ruleset >"results/ruleset_${mode}_c${cycle}.json"
  fi
}

for (( cycle=1; cycle<=CYCLES; cycle++ )); do
  modes=(flat routed_open segmented_acl)
  [[ "${ND_SMOKE:-0}" == 1 ]] && modes=(flat) # only test L2 without kernel firewall
  for mode in "${modes[@]}"; do
    echo; echo "=== Cycle $cycle / $mode ==="
    make_topology "$mode"
    start_services "$cycle" "$mode"
    probe_all "$cycle" "$mode"
    cleanup
  done
done
python3 "$BASE/analyze.py"
python3 "$BASE/make_figures.py"
sha256sum "$BASE/run_lab.sh" "$BASE/service.py" "$BASE/probe.py" "$BASE/analyze.py" > results/source_sha256.txt
printf '\nDone. Results: %s/results\n' "$BASE"

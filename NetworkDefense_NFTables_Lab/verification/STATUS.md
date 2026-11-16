# Scope of validation in ChatGPT environment

- Test run: CYCLES=1 REPEATS=2 bash run_lab.sh --smoke-only
- Kernel L2 bridge/veth, service listeners, TCP connections and benign marker relay were exercised in an isolated Linux network/user/mount namespace.
- Flat: 8 of 8 direct TCP attempts succeeded; WEB -> DATABASE 2 of 2 succeeded; marker relayed.
- This is a *smoke test of the harness only*, not a completed nftables experiment. Values must not be used as evidence of a firewall control.
- nftables was not available, and ip_forward could not be enabled because /proc/sys is read-only in this environment; segmented firewall result requires a new run on a dedicated Ubuntu VM.

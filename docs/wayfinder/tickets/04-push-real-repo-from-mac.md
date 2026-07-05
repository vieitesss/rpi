<!-- child-of: Self-hosted private git server (Forgejo on Tailscale) -->
# Push a real private repo from the Mac end-to-end

- label: wayfinder:task
- status: open
- assignee:
- blocked-by: Expose Forgejo SSH over Tailscale and verify a clone

## Question

From the Mac over Tailscale: register the SSH key, create a private repo in
Forgejo, add the remote, and `git push` a real repo. Confirm it round-trips
(clone back, browse in the web UI). This is the acceptance test for the dev
server being genuinely usable from the primary client.

Hand the human a precise checklist for the Mac-side steps (SSH config, key
upload). Answer records the working clone URL form and any Mac SSH config.

# apt repository sources

These files drive the signed apt repository published to GitHub Pages by
`.github/workflows/release.yml` (job `publish-apt-repo`).

- `conf/distributions` — reprepro distribution config. `__GPG_FINGERPRINT__` is
  replaced in CI with the fingerprint of the imported signing key, so it never
  needs to be committed.

The signing key's **public** counterpart is exported in CI from the
`GPG_PRIVATE_KEY` secret and published as `public.key` at the repo root, so it
always matches the key that signed `Release`. It is intentionally not committed.

## One-time setup (maintainer)

```bash
# Passphrase-less signing key (simplest for CI)
gpg --batch --quick-generate-key "Drone Streamer Portal <bewr@pm.me>" rsa4096 sign never
gpg --armor --export-secret-keys bewr@pm.me   # paste into the GPG_PRIVATE_KEY repo secret
```

Then enable GitHub Pages (Settings → Pages → Deploy from a branch → `gh-pages` / root).

## Consuming the repository

```bash
curl -fsSL https://likt0r.github.io/drone-streamer-portal/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/drone-streamer-portal.gpg
echo "deb [signed-by=/usr/share/keyrings/drone-streamer-portal.gpg] https://likt0r.github.io/drone-streamer-portal stable main" \
  | sudo tee /etc/apt/sources.list.d/drone-streamer-portal.list
sudo apt update && sudo apt install drone-streamer-portal
```

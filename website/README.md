# Website

Public site: https://yapp.now/ · Repository: https://github.com/avardaan/yapp

GitHub Pages deploys `website/` through `.github/workflows/pages.yml` on pushes
to main. Configure Settings → Pages → Source: GitHub Actions. Preserve the custom
domain `yapp.now` and Enforce HTTPS. Never upload the repository root as the site.

The download button links the current versioned DMG, so users download
`yapp-<version>-arm64.dmg`. After uploading a release, `./script/set-download-link.sh`
checks the asset is public and updates the link. The release script also creates
a stable `Yapp-arm64.dmg`; keep uploading it so older `releases/latest/download/`
links keep working. The Sparkle ZIP/appcast uses versioned URLs;
publish the appcast only after that ZIP is uploaded.

DNS at Porkbun: root ALIAS → avardaan.github.io; www CNAME → avardaan.github.io.
Nameservers remain at Porkbun.

Pill design: #1C1C1E at 99% opacity, amber #F4B241, bars at 78% of that amber.
The website illustrates recording on hover; the app responds to microphone audio.

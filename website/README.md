# Website

Public site: https://yapp.now/ · Repository: https://github.com/avardaan/yapp

GitHub Pages deploys `website/` through `.github/workflows/pages.yml` on pushes
to main. Configure Settings → Pages → Source: GitHub Actions. Preserve the custom
domain `yapp.now` and Enforce HTTPS. Never upload the repository root as the site.

The download button uses GitHub’s stable latest-asset URL:
`https://github.com/avardaan/yapp/releases/latest/download/Yapp-arm64.dmg`.
Upload `Yapp-arm64.dmg` and its checksum before marking each release latest.
The release script creates these alongside versioned artifacts. Keep versioned
assets for existing direct links. The Sparkle ZIP/appcast uses versioned URLs;
publish the appcast only after that ZIP is uploaded.

DNS at Porkbun: root ALIAS → avardaan.github.io; www CNAME → avardaan.github.io.
Nameservers remain at Porkbun.

Pill design: #1C1C1E at 99% opacity, amber #F4B241, bars at 78% of that amber.
The website illustrates recording on hover; the app responds to microphone audio.

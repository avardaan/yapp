# Website

Public site: https://yapp.now/ · Repository: https://github.com/avardaan/yapp

GitHub Pages deploys `website/` through `.github/workflows/pages.yml` on pushes
to main. Configure Settings → Pages → Source: GitHub Actions. Preserve the custom
domain `yapp.now` and Enforce HTTPS. Never upload the repository root as the site.

The download button links to the latest GitHub Release asset. Its filename must
match the uploaded DMG; update it when publishing a new version.

DNS at Porkbun: root ALIAS → avardaan.github.io; www CNAME → avardaan.github.io.
Nameservers remain at Porkbun.

Pill design: #1C1C1E at 99% opacity, amber #F4B241, bars at 78% of that amber.
The website illustrates recording on hover; the app responds to microphone audio.

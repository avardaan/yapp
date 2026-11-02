# Yapp website

Static GitHub Pages landing page: https://yapp.now/.
Public website/download repository: https://github.com/avardaan/yapp-releases.
Only website files and release assets belong there; never push the app repository.

Publish index.html and CNAME to the public repository root. Pages deploys from
main / (root). The download points to the latest GitHub Release asset; update
its filename and displayed version when publishing a new version.

Porkbun DNS: root ALIAS → avardaan.github.io; www CNAME → avardaan.github.io.
Nameservers stay at Porkbun. Enable Enforce HTTPS once GitHub issues the certificate.

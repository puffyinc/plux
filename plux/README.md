# plux 🌅

Plux is a rendering engine using VisTrace implemented in GMod.

# Features

-   Global illumination
-   PBR
-   MIS
-   HDRI lighting and analytical lights
-   PSR + CSFR for accurate G-buffers
-   Denoising using OIDN with [gmdenoiser](https://github.com/yogwoggf/gmdenoiser)
-   Russian Roulette
-   Absorption

# Showcase

`TBD`

# Source Code

-   `app.lua` contains the code which runs and saves the pathtracer output.
-   `pathtracer.lua` contains the actual pathtracer.
-   `settings.lua` contains the settings for the pathtracer.
-   `adjustments.lua` contains the Context Menu extension for lights.
-   The rest of the files are libraries primarily used by the above files.

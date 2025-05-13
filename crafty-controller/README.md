[![Crafty Logo](https://gitlab.com/crafty-controller/crafty-4/-/raw/master/app/frontend/static/assets/images/logo_long.svg)](https://craftycontrol.com)

[![GitHub Release][releases-shield]][releases]
[![License][license-shield]][license]

# Home Assistant Add-on: Crafty Controller

> Python based Control Panel for your Minecraft Server(s)

## What is Crafty Controller?

Crafty Controller is a Minecraft Server Control Panel / Launcher. The purpose
of Crafty Controller is to launch a Minecraft Server in the background and present
a web interface for the server administrators to interact with their servers. C

This add-on integrates Crafty Controller directly into your Home Assistant instance, providing a convenient way to manage your Minecraft servers alongside your smart home.

### Features

- Manage multiple Minecraft servers
- Server stats monitoring
- Remote console access
- Server backups
- User management with permissions
- Server scheduling
- Support for multiple Minecraft versions and modpacks
- Currently supports amd64 arch

---

## Documentation

### Installation

Follow these steps to get the add-on installed on your system:

1. Navigate in your Home Assistant frontend to **Supervisor** -> **Add-on Store**.
2. Add the repository URL: `https://github.com/elysiandc/hassio-addons`
3. Find the "Crafty Controller" add-on and click it.
4. Click on the "INSTALL" button.

### How to use

See the [detailed documentation](DOCS.md) for complete usage instructions.
Crafty specific documentation available on [Crafty Docs](https://docs.craftycontrol.com)

---

## Meta

Project Homepage - https://craftycontrol.com
Discord Server - https://discord.gg/9VJPhCE
Git Repository - https://gitlab.com/crafty-controller/crafty-4
Docker Hub - [arcadiatechnology/crafty-4](https://hub.docker.com/r/arcadiatechnology/crafty-4)

> \***\*⚠ 🔻WARNING: [WSL/WSL2 | WINDOWS 11 | DOCKER DESKTOP]🔻\*\*** <br>
> BE ADVISED! Upstream is currently broken for Minecraft running on **Docker under WSL/WSL2, Windows 11 / DOCKER DESKTOP!** <br>
> On '**Stop**' or '**Restart**' of the MC Server, there is a 90% chance the World's Chunks will be shredded irreparably! <br>
> Please only run Docker on Linux, If you are using Windows we have a portable installs found here: [Latest-Stable](https://gitlab.com/crafty-controller/crafty-4/-/releases), [Latest-Development](https://gitlab.com/crafty-controller/crafty-4/-/jobs/artifacts/dev/download?job=win-dev-build)

---

## License

MIT License

[releases-shield]: https://img.shields.io/github/release/elysiandc/hassio-addons.svg
[releases]: https://github.com/elysiandc/hassio-addons/releases
[license-shield]: https://img.shields.io/github/license/elysiandc/hassio-addons.svg
[license]: https://github.com/elysiandc/hassio-addons/blob/master/LICENSE

# Home Assistant Add-on: Crafty Controller

## Installation

Follow these steps to get the add-on installed on your system:

1. Navigate in your Home Assistant frontend to **Supervisor** -> **Add-on Store**.
2. Add the repository URL: `https://github.com/elysiandc/hassio-addons`
3. Find the "Crafty Controller" add-on and click it.
4. Click on the "INSTALL" button.

## How to use

1. Start the add-on.
2. Check the logs of the add-on to see if everything went well.
3. Open the web UI for the add-on. You can access this either:
   - Through the Sidebar (when Ingress is enabled)
   - Via the direct web UI URL: `https://your-ip:8433` (or with HTTPS if SSL is enabled)

## Configuration

### Password Requirements

The password must meet these minimum requirements:

- At least 12 characters long
- Must contain at least one letter
- Must contain at least one number
- Special characters are allowed but not required

Example configuration:

```yaml
username: "admin"
password: "YourSecurePassword123"
```

### Option: `log_level`

The `log_level` option controls the level of log output by the add-on and can
be changed to be more or less verbose, which might be useful when you are
dealing with an unknown issue. Possible values are:

- `trace`: Show every detail, like all called internal functions.
- `debug`: Shows detailed debug information.
- `info`: Normal (usually) interesting events.
- `warning`: Exceptional occurrences that are not errors.
- `error`: Runtime errors that do not require immediate action.
- `fatal`: Something went terribly wrong. Add-on becomes unusable.

Please note that each level automatically includes log messages from a
more severe level, e.g., `debug` also shows `info` messages. By default,
the `log_level` is set to `info`, which is the recommended setting unless
you are troubleshooting.

### Data Storage Locations

The addon stores data in the following locations:

- `/share/crafty/servers`: Minecraft server files
- `/share/crafty/import`: Import directory
- `/share/crafty/config`: Crafty configuration
- `/backup/crafty`: Backup files

All data persists across addon restarts and updates.

## Ports

This add-on exposes the following ports:

- 8443/tcp: Web interface outside Home Assistant
- 8433/tcp: Used for Ingress
- 25565-25570/tcp: Default Minecraft server ports

You can use these ports to access your Minecraft servers from outside your network. Remember to configure port forwarding on your router if needed.

## Initial Setup

When you first access Crafty Controller, you'll need to complete the initial setup:

1. Create your admin account
2. Configure Crafty settings

## Adding Minecraft Servers

After the initial setup, you can add Minecraft servers through the Crafty Controller web interface:

1. Go to the Servers tab
2. Click "Add Server"
3. Follow the wizard to set up your Minecraft server

## Support

If you have questions or need help with Crafty Controller itself, please visit the [Crafty Controller documentation](https://docs.craftycontrol.com/) or the [Crafty Controller Discord](https://discord.gg/S8Q3AamhCk).

For issues with the add-on integration, please open an issue on the [GitHub repository](https://github.com/elysiandc/hassio-addons).

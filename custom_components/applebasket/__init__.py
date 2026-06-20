"""Apple Basket — Reminders lists as native HA to-do entities.

Config-entry integration (YAML/discovery platform setup is gone in modern HA).
Add it once via Settings -> Devices & Services -> Add Integration -> Apple Basket;
the entry persists across restarts. No options to fill in — the HA URL and token
live on the Mac side, not here.
"""
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant

PLATFORMS = ["todo"]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)

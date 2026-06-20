"""One TodoListEntity per Reminders list.

State flows in on `applebasket_state` events (full open-items snapshot, reconciled
idempotently). User actions fire `applebasket_command` events the Mac picks up over
its WebSocket and applies to Reminders. No optimistic update: the next snapshot
(~1s) reflects the change. That avoids uid reconciliation and divergence bugs.
"""
from __future__ import annotations

from homeassistant.components.todo import (
    TodoItem,
    TodoItemStatus,
    TodoListEntity,
    TodoListEntityFeature,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import Event, HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback

STATE_EVENT = "applebasket_state"
COMMAND_EVENT = "applebasket_command"


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    entities: dict[str, AppleBasketList] = {}

    @callback
    def handle_state(event: Event) -> None:
        new: list[AppleBasketList] = []
        for block in event.data.get("lists", []):
            name = block.get("list")
            if not name:
                continue
            ent = entities.get(name)
            if ent is None:
                ent = AppleBasketList(name)
                entities[name] = ent
                new.append(ent)
            ent.set_items(block.get("items", []))
        if new:
            async_add_entities(new)

    entry.async_on_unload(hass.bus.async_listen(STATE_EVENT, handle_state))


class AppleBasketList(TodoListEntity):
    _attr_should_poll = False
    _attr_supported_features = (
        TodoListEntityFeature.CREATE_TODO_ITEM
        | TodoListEntityFeature.UPDATE_TODO_ITEM
        | TodoListEntityFeature.DELETE_TODO_ITEM
    )

    def __init__(self, name: str) -> None:
        self._attr_name = name
        self._attr_unique_id = f"applebasket_{name}"
        self._attr_todo_items = []

    @callback
    def set_items(self, items: list[dict]) -> None:
        self._attr_todo_items = [
            TodoItem(
                uid=i["uid"],
                summary=i["summary"],
                status=TodoItemStatus.NEEDS_ACTION,
            )
            for i in items
            if i.get("uid") and i.get("summary")
        ]
        if self.hass is not None:
            self.async_write_ha_state()

    def _fire(self, payload: dict) -> None:
        self.hass.bus.async_fire(COMMAND_EVENT, payload)

    async def async_create_todo_item(self, item: TodoItem) -> None:
        self._fire({"op": "add", "list": self._attr_name, "summary": item.summary})

    async def async_update_todo_item(self, item: TodoItem) -> None:
        # ponytail: only status->complete is wired; summary rename deferred until needed.
        if item.status == TodoItemStatus.COMPLETED:
            self._fire({"op": "complete", "uid": item.uid})

    async def async_delete_todo_items(self, uids: list[str]) -> None:
        for uid in uids:
            self._fire({"op": "delete", "uid": uid})

'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('vehicle inventory id is always derived from the server plate', () => {
    const source = read('server.lua');

    assert.match(source, /data\.id\s*=\s*\(invType == 'glovebox' and 'glove' or 'trunk'\) \.\. plate/);
    assert.doesNotMatch(source, /if not data\.id then\s*data\.id\s*=\s*\(invType == 'glovebox'/);
});

test('dumpsters require a real model and canonical numeric net id', () => {
    const source = read('server.lua');

    assert.match(source, /dumpsterModels\[GetEntityModel\(entity\)\] == true/);
    assert.match(source, /inventoryId\s*=\s*\('dumpster-%s-%s'\):format\(bucket, netid\)/);
    assert.match(source, /getDumpsterEntityFromCoords\(data/);
});

test('normal personal stash opens are bound to the requesting player', () => {
    const source = read('modules/inventory/server.lua');

    assert.match(source, /owner = \(not player or ignoreSecurityChecks\) and data\.owner or player\?\.owner/);
});

test('client inventory inspection is limited to the authorized open inventory', () => {
    const source = read('server.lua');

    assert.match(source, /id ~= source and id ~= playerInventory\.id and id ~= playerInventory\.open then return end/);
    assert.match(source, /playerInventory\.open ~= inventory\.id/);
    assert.match(source, /getClientAccessibleInventory\(source, target\)/);
    assert.match(source, /getClientAccessibleInventory\(source, id\)/);
    assert.match(source, /GetEntityCoords\(right\.player\.ped\)\) > 3\.0/);
});

test('weapon attachment mutations require a real component and free component type', () => {
    const source = read('modules/inventory/server.lua');

    assert.match(source, /if not componentItem\?\.component then return false end/);
    assert.match(source, /installed\.type == componentItem\.type/);
    assert.match(source, /RemoveItem\(inventory, componentItem, 1, component\.metadata, componentSlot\)/);
});

test('cash has one stored identity and cash remains a compatibility alias', () => {
    const items = read('data/items.lua');
    const sharedItems = read('modules/items/shared.lua');

    assert.match(items, /\['money'\]\s*=\s*\{/);
    assert.doesNotMatch(items, /\['cash'\]\s*=\s*\{/);
    assert.match(sharedItems, /ItemList\.cash\s*=\s*ItemList\.money/);
});

test('Miami adapter maps ox stack identity to QB uniqueness', () => {
    const adapter = read('web/rs-ui/rs-ox-adapter.js');
    const app = read('web/rs-ui/app.js');

    assert.match(adapter, /unique:\s*def\.stack === false/);
    assert.match(app, /canonicalMetadata\(sourceMetadata\)/);
    assert.match(app, /response\.data !== true && !this\.applyInventorySnapshot/);
});


test('RS UI cross-inventory transfers are server-authoritative', () => {
    const app = read('web/rs-ui/app.js');

    const moveStart = app.indexOf('moveItemBetweenInventories(item, sourceInventoryType)');
    const moveEnd = app.indexOf('getUiZoom()', moveStart);
    const moveBlock = app.slice(moveStart, moveEnd);
    assert.match(moveBlock, /RS SAFE-TRANSFER/);
    assert.doesNotMatch(moveBlock, /delete sourceInventory\[/);
    assert.doesNotMatch(moveBlock, /targetInventory\[targetSlot\]\s*=/);
    assert.doesNotMatch(moveBlock, /sourceItem\.amount\s*-=/);

    const dragStart = app.indexOf('handleItemDrop(targetInventoryType, targetSlot)');
    const dragEnd = app.indexOf('async handlePurchase', dragStart);
    const dragBlock = app.slice(dragStart, dragEnd);
    assert.match(dragBlock, /Server-authoritative stack/);
    assert.doesNotMatch(dragBlock, /delete sourceInventory\[/);
    assert.doesNotMatch(dragBlock, /targetInventory\[targetSlotNumber\]\s*=/);
    assert.doesNotMatch(dragBlock, /sourceItem\.amount\s*-=/);
});

test('ground drop destination is created before the player stack is reduced', () => {
    const source = read('modules/inventory/server.lua');
    const dropStart = source.indexOf('local function dropItem');
    const dropEnd = source.indexOf("lib.callback.register('ox_inventory:swapItems'", dropStart);
    const dropBlock = source.slice(dropStart, dropEnd);

    const createIndex = dropBlock.indexOf('Inventory.Create(dropId');
    const reduceIndex = dropBlock.indexOf('fromData.count -= data.count');
    assert.ok(createIndex > -1 && reduceIndex > -1 && createIndex < reduceIndex);
    assert.match(dropBlock, /RS SAFE-TRANSFER/);
});


test('moving-vehicle ammo reload cannot throw before the authoritative server update', () => {
    const source = read('client.lua');
    const ammoStart = source.indexOf('if data.ammo then');
    const ammoEnd = source.indexOf('elseif data.component then', ammoStart);
    const ammoBlock = source.slice(ammoStart, ammoEnd);

    assert.ok(ammoStart > -1 && ammoEnd > ammoStart);
    assert.match(ammoBlock, /local reloadDeadline = GetGameTimer\(\) \+ 1500/);
    assert.match(ammoBlock, /SetAmmoInClip\(playerPed, currentWeapon\.hash, math\.min\(newAmmo, clipSize\)\)/);
    assert.doesNotMatch(ammoBlock, /lib\.waitFor\(function\(\)\s*RefillAmmoInstantly/);

    const reloadGuard = ammoBlock.indexOf('local reloadDeadline');
    const authoritativeUpdate = ammoBlock.indexOf("lib.callback.await('ox_inventory:updateWeapon'");
    assert.ok(reloadGuard > -1 && authoritativeUpdate > reloadGuard);
});


test('Qbox vehicle capacity is derived from the server-resolved model/class path', () => {
    const inventory = read('modules/inventory/server.lua');
    const bridge = read('modules/bridge/qbx/server.lua');

    assert.match(inventory, /model = GetEntityModel\(entity\)/);
    assert.match(inventory, /server\.getVehicleClass\(entity\)/);
    assert.match(bridge, /pcall\(QBX\.GetVehicleClass, QBX, model\)/);
    assert.doesNotMatch(inventory, /class\s*=\s*data\.class/);
});

test('persistent inventory saves restore dirty state and retain failed player logout snapshots', () => {
    const inventory = read('modules/inventory/server.lua');
    const mysql = read('modules/mysql/server.lua');
    const server = read('server.lua');

    assert.match(inventory, /pendingPlayerSaves/);
    assert.match(inventory, /retainPendingPlayerSave\(inv\.owner, inv\)/);
    assert.match(inventory, /if not ok or result == nil then\s*inv\.changed = true/s);
    assert.match(inventory, /inv\.saving = true/);
    assert.match(mysql, /results\[1\] = resp ~= nil/);
    assert.match(server, /Inventory\.ConsumePendingPlayerSave\(player\.identifier\)/);
    assert.match(server, /Inventory\.RestorePendingPlayerSave\(player\.identifier, data\)/);
});

test('database startup failures are not mistaken for missing schema', () => {
    const mysql = read('modules/mysql/server.lua');

    assert.match(mysql, /pcall\(MySQL\.query\.await, "SHOW TABLES LIKE 'ox_inventory'"\)/);
    assert.match(mysql, /Unable to inspect ox_inventory schema; skipping automatic migrations/);
});

test('secondary inventory mutations continuously revalidate access and session identity', () => {
    const inventory = read('modules/inventory/server.lua');

    assert.match(inventory, /function Inventory\.CanAccess\(/);
    assert.match(inventory, /GetPlayerRoutingBucket\(source\) ~= inv\.bucket/);
    assert.match(inventory, /Inventory\.CanAccess\(secondary, playerInventory, source\)/);
    assert.match(inventory, /Inventories\[source\] ~= playerInventory/);
});

test('drops derive bucket and instance on the server and late joins only receive visible drops', () => {
    const inventory = read('modules/inventory/server.lua');
    const server = read('server.lua');

    assert.match(inventory, /bucket = GetPlayerRoutingBucket\(source\)/);
    assert.match(inventory, /instance = Player\(source\)\.state\.instance/);
    assert.match(inventory, /function Inventory\.GetVisibleDrops\(source\)/);
    assert.match(server, /Inventory\.GetVisibleDrops\(player\.source\)/);
});

test('crafting completion is server-timed, session-bound, locked and rollback protected', () => {
    const crafting = read('modules/crafting/server.lua');

    assert.match(crafting, /local startedAt = GetGameTimer\(\)/);
    assert.match(crafting, /GetGameTimer\(\) - startedAt \+ 150 < duration/);
    assert.match(crafting, /Inventory\(source\) ~= left/);
    assert.match(crafting, /for slot = 1, left\.slots do addLock\(slot\) end/);
    assert.match(crafting, /restoreCraftSnapshot/);
    assert.match(crafting, /xpcall\(function\(\)/);
});

test('shop purchase is access-bound, serialized and rollback protected', () => {
    const shops = read('modules/shops/server.lua');

    assert.match(shops, /canAccessShop\(source, playerInv, shop\)/);
    assert.match(shops, /shop-%s:slot-%s/);
    assert.match(shops, /for slot = 1, playerInv\.slots do/);
    assert.match(shops, /restorePurchaseSnapshot/);
    assert.match(shops, /purchase currency removal failed/);
});

test('weapon ammo and component mutations update aggregate inventory weight', () => {
    const inventory = read('modules/inventory/server.lua');

    assert.match(inventory, /local function updateWeaponWeight/);
    assert.match(inventory, /inventory\.weight \+= weapon\.weight - previousWeight/);
    assert.match(inventory, /if value > currentAmmo then return false end/);
    assert.match(inventory, /if value < currentAmmo then return false end/);
});

test('license purchases require server-side proximity and inventory locking', () => {
    const server = read('server.lua');

    assert.match(server, /GetEntityCoords\(ped\) - license\.coords\) > 3\.0/);
    assert.match(server, /local activeSlots <close> = GetLocks\(lockIds\)/);
});

test('manifest ships only active Miami UI assets and current image formats', () => {
    const manifest = read('fxmanifest.lua');

    assert.doesNotMatch(manifest, /lua54\s+['"]yes['"]/);
    assert.doesNotMatch(manifest, /web\/rs-ui\/\*\*\/\*/);
    assert.match(manifest, /web\/images\/\*\.PNG/);
    assert.match(manifest, /web\/images\/\*\.webp/);
    assert.match(manifest, /use_experimental_fxv2_oal/);
});


test('admin inspect mode is enforced server-side as read-only', () => {
    const inventory = read('modules/inventory/server.lua');

    assert.match(inventory, /playerInventory\.inspect = inventory\.id/);
    assert.match(inventory, /if playerInventory\.inspect then return false end/);
    assert.match(inventory, /self\.inspect = nil/);
});


test('confiscation and restoration are atomic, merge-safe, and preserve recovery on failure', () => {
    const inventory = read('modules/inventory/server.lua');
    const mysql = read('modules/mysql/server.lua');

    assert.match(mysql, /function db\.confiscatePlayer/);
    assert.match(mysql, /MySQL\.transaction\.await/);
    assert.match(mysql, /Query\.UPSERT_STASH/);
    assert.match(mysql, /Query\.UPDATE_PLAYER/);
    assert.match(mysql, /function db\.returnConfiscatedPlayer/);
    assert.match(mysql, /Query\.DELETE_STASH/);
    assert.match(mysql, /DELETE FROM ox_inventory WHERE owner = \? AND name = \?/);

    assert.match(inventory, /local function mergeConfiscatedItems/);
    assert.match(inventory, /local inventory = table\.deepclone\(inv\.items\)/);
    assert.match(inventory, /if totalWeight > inv\.maxWeight then return nil, nil, 'inventory_overweight' end/);
    assert.match(inventory, /recovery row was preserved/);
    assert.match(inventory, /db\.confiscatePlayer\(inv\.owner, recoveryName, snapshot\)/);
    assert.match(inventory, /db\.returnConfiscatedPlayer\(inv\.owner, recoveryName, persistedData\)/);
    assert.doesNotMatch(inventory, /MySQL\.update\.await\('DELETE FROM ox_inventory WHERE name = \?'/);
});

test('durable inventory moves block concurrent mutations and batch saves', () => {
    const inventory = read('modules/inventory/server.lua');

    assert.match(inventory, /local transaction <close> = lockInventoryTransaction\(inv\)/);
    assert.match(inventory, /if inv\.transactionLocked then return false, 'inventory_locked' end/);
    assert.match(inventory, /if inv\.saving or inv\.transactionLocked then return end/);
    assert.match(inventory, /for slot = 1, inv\.slots do/);
    assert.match(inventory, /local lockIds = inventorySlotLockIds\(inv, 'teardown'\)/);
    assert.match(inventory, /Waiting for active inventory transaction before removing/);
});

test('returned inventories apply the authoritative merged weight on the client', () => {
    const inventory = read('modules/inventory/server.lua');
    const client = read('client.lua');

    assert.match(inventory, /inventoryReturned', inv\.id, \{ inventory, totalWeight \}/);
    assert.match(client, /updateInventory\(items, tonumber\(data\[2\]\) or tonumber\(data\[3\]\) or 0\)/);
});


test('SetMetadata normalizes payloads and preserves aggregate weight accounting', () => {
    const inventory = read('modules/inventory/server.lua');
    const start = inventory.indexOf('function Inventory.SetMetadata');
    const end = inventory.indexOf("exports('SetMetadata'", start);
    const block = inventory.slice(start, end);

    assert.match(block, /local newMetadata = type\(metadata\) == 'table' and table\.deepclone\(metadata\) or \{ type = metadata or nil \}/);
    assert.match(block, /slot\.weight = Inventory\.SlotWeight\(item, slot\)/);
    assert.match(block, /inv\.weight \+= slot\.weight - previousWeight/);
    assert.ok(block.indexOf('Utils.IsValidImageUrl(newMetadata.imageurl)') < block.indexOf('slot.metadata = newMetadata'));
    assert.doesNotMatch(block, /if metadata\.weight then/);
});

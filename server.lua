-- Modified by RealitySucksRP on 2026-08-24.
-- Changes: server-side inventory validation and compatibility updates.
-- Based on ox_inventory 2.47.9; distributed under GPL-3.0.

if not lib then return end

require 'modules.bridge.server'
require 'modules.crafting.server'
require 'modules.shops.server'
require 'modules.pefcl.server'

if GetConvar('inventory:versioncheck', 'true') == 'true' then
    lib.versionCheck('overextended/ox_inventory')
end

local TriggerEventHooks = require 'modules.hooks.server'
local db = require 'modules.mysql.server'
local Items = require 'modules.items.server'
local Inventory = require 'modules.inventory.server'
local Utils = require 'modules.utils.server'
local GetLocks = require 'modules.locks'

---@param player table
---@param data table?
--- player requires source, identifier, and name
--- optionally, it should contain jobs/groups, sex, and dateofbirth
function server.setPlayerInventory(player, data)
    while not shared.ready do Wait(0) end

    local recoveredPendingSave = false

    if not data then
        data = Inventory.ConsumePendingPlayerSave(player.identifier)

        if data then
            recoveredPendingSave = true
        else
            local loadError
            data, loadError = db.loadPlayer(player.identifier)

            if loadError then
                lib.print.error(('Failed to load inventory for %s: %s'):format(player.identifier, loadError))
                return false
            end
        end
    end

    local inventory = {}
    local totalWeight = 0

    if type(data) == 'table' then
        local ostime = os.time()

        for _, v in pairs(data) do
            if type(v) == 'number' or not v.count or not v.slot then
                if server.convertInventory then
                    inventory, totalWeight = server.convertInventory(player.source, data)
                    break
                else
                    return error(('Inventory for player.%s (%s) contains invalid data. Ensure you have converted inventories to the correct format.')
                    :format(player.source, GetPlayerName(player.source)))
                end
            else
                local item = Items(v.name)

                if item then
                    v.metadata = Items.CheckMetadata(v.metadata or {}, item, v.name, ostime)
                    local weight = Inventory.SlotWeight(item, v)
                    totalWeight = totalWeight + weight

                    inventory[v.slot] = { name = item.name, label = item.label, weight = weight, slot = v.slot, count = v
                    .count, description = item.description, metadata = v.metadata, stack = item.stack, close = item
                    .close }
                end
            end
        end
    end

    player.source = tonumber(player.source)
    local inv = Inventory.Create(player.source, player.name, 'player', shared.playerslots, totalWeight,
        shared.playerweight, player.identifier, inventory)

    if not inv then
        if recoveredPendingSave then Inventory.RestorePendingPlayerSave(player.identifier, data) end
        return false
    end

    inv.player = server.setPlayerData(player)

    if recoveredPendingSave then
        inv.changed = true
        shared.info(('Restored pending in-memory inventory snapshot for %s.'):format(player.identifier))
    end

    local pedDeadline = GetGameTimer() + 10000
    repeat
        if Inventory(player.source) ~= inv or not GetPlayerName(player.source) then
            Inventory.Remove(inv)
            return false
        end

        inv.player.ped = GetPlayerPed(player.source)
        if inv.player.ped ~= 0 then break end
        Wait(0)
    until GetGameTimer() >= pedDeadline

    if inv.player.ped == 0 then
        lib.print.error(('Timed out waiting for a player ped while loading inventory for %s.'):format(player.identifier))
        Inventory.Remove(inv)
        return false
    end

    if server.syncInventory then server.syncInventory(inv) end
    TriggerClientEvent('ox_inventory:setPlayerInventory', player.source, Inventory.GetVisibleDrops(player.source), inventory, totalWeight,
        inv.player)

    return inv
end

exports('setPlayerInventory', server.setPlayerInventory)
AddEventHandler('ox_inventory:setPlayerInventory', server.setPlayerInventory)

local registeredDumpsters = {}

-- Keep this in sync with Inventory.Dumpsters in modules/inventory/client.lua.
-- Dumpster identities and coordinates arrive from an untrusted client, so the
-- server must resolve an actual allowed object before creating random loot.
local dumpsterModels = {
    [218085040] = true,
    [666561306] = true,
    [-58485588] = true,
    [-206690185] = true,
    [1511880420] = true,
    [682791951] = true,
}

---@param entity number
---@return boolean
local function isValidDumpsterEntity(entity)
    return entity > 0
        and DoesEntityExist(entity)
        and GetEntityType(entity) == 3
        and dumpsterModels[GetEntityModel(entity)] == true
end

---@param coords vector3
---@return number?
local function getDumpsterEntityFromCoords(coords)
    if type(coords) ~= 'vector3' then return end

    local objects = GetAllObjects()

    for i = 1, #objects do
        local entity = objects[i]

        if isValidDumpsterEntity(entity) and #(GetEntityCoords(entity) - coords) < 1.0 then
            return entity
        end
    end
end

---@param coords vector3
---@return number?
local function getDumpsterFromCoords(coords)
    local found

    for i = 1, #registeredDumpsters do
        local distance = #(coords - registeredDumpsters[i])

        if distance < 0.1 then
            found = i
            break
        end
    end

    return found
end

---@param playerPed number
---@param stash OxInventory
---@return vector3?
local function getClosestStashCoords(playerPed, stash)
    local playerCoords = GetEntityCoords(playerPed)
    local distance = stash.distance or 10
    local coordinates = stash.coords

    if not coordinates then return end

    if type(coordinates) == 'table' then
        for i = 1, #coordinates do
            local coords = coordinates[i] --[[@as vector3]]

            if #(coords - playerCoords) < distance then
                return coords
            end
        end

        return
    end

    return #(coordinates - playerCoords) < distance and coordinates or nil
end

---@param source number
---@param invType string
---@param data? string | number | table | vector3
---@param ignoreSecurityChecks boolean?
---@return table | false | nil, table | false | nil, string?
local function openInventory(source, invType, data, ignoreSecurityChecks)
    -- RS: a nil invType is the player's OWN inventory -- client.openInventory()
    -- with no arguments, which is exactly what the TAB keybind sends. The type
    -- guard is there to reject malformed types from a modified client; when it
    -- also rejected nil, every own-inventory open came back `false`, which the
    -- client drops silently (no notify, no F8 line). Upstream allows nil.
    if Inventory.Lock or (invType ~= nil and type(invType) ~= 'string') then return false end

    local left = Inventory(source)
    local right, closestCoords

    if not left then return end

    left:closeInventory(true)
    Inventory.CloseAll(left, source)

    if invType == 'player' and data == source then
        data = nil
    end

    local playerPed = left.player.ped
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then return end

    if data then
        local isDataTable = type(data) == 'table'

        if invType == 'stash' then
            right = Inventory(data, left, ignoreSecurityChecks)
            if right == false then return false end
        elseif isDataTable then
            if data.netid then
                if invType ~= 'glovebox' and invType ~= 'trunk' then return end
                if type(data.netid) ~= 'number' then return end

                local entity = NetworkGetEntityFromNetworkId(data.netid)

                if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return end

                if not ignoreSecurityChecks then
                    if GetPlayerRoutingBucket(source) ~= GetEntityRoutingBucket(entity) then return end
                    if #(GetEntityCoords(playerPed) - GetEntityCoords(entity)) > 16 then return end
                end

                if invType == 'glovebox' then
                    if not ignoreSecurityChecks and GetVehiclePedIsIn(playerPed, false) ~= entity then
                        return
                    end
                end

                if invType == 'trunk' then
                    local lockStatus = ignoreSecurityChecks and 0 or GetVehicleDoorLockStatus(entity)

                    -- 0: no lock; 1: unlocked; 8: boot unlocked
                    if lockStatus > 1 and lockStatus ~= 8 then
                        return false, false, 'vehicle_locked'
                    end
                end

                local plate = (invType == 'glovebox' or invType == 'trunk') and GetVehicleNumberPlateText(entity)

                if plate then
                    if server.trimplate then plate = string.strtrim(plate) end
                    plate = plate:upper()

                    -- Keep every vehicle storage reference on one server-resolved,
                    -- canonical inventory id.
                    data.id = (invType == 'glovebox' and 'glove' or 'trunk') .. plate
                end

                data.type = invType
                right = Inventory(data)

                if right and data.netid ~= right.netid then
                    local invEntity = NetworkGetEntityFromNetworkId(right.netid)
                    local invPlate = invEntity > 0 and DoesEntityExist(invEntity) and GetVehicleNumberPlateText(invEntity) or nil

                    if invPlate and server.trimplate then invPlate = string.strtrim(invPlate) end
                    if invPlate then invPlate = invPlate:upper() end

                    if not invPlate or (plate and invPlate ~= plate) then
                        Inventory.Remove(right)
                        right = Inventory(data)
                    end
                end

                if right then
                    right.entityId = entity
                    right.netid = data.netid
                    right.bucket = GetEntityRoutingBucket(entity)
                end
            elseif invType == 'drop' then
                right = Inventory(data.id)
            else
                return
            end
        elseif invType == 'policeevidence' then
            if ignoreSecurityChecks or server.hasGroup(left, shared.police) then
                right = Inventory(('evidence-%s'):format(data))
            end
        elseif invType == 'dumpster' then
            if shared.networkdumpsters then
                local entity = getDumpsterEntityFromCoords(data --[[@as vector3]])

                if not entity then return end

                local coords = GetEntityCoords(entity)

                if not ignoreSecurityChecks and #(GetEntityCoords(playerPed) - coords) > 10 then return end

                local bucket = GetPlayerRoutingBucket(source)
                local dumpsterId = getDumpsterFromCoords(coords)
                right = dumpsterId and Inventory(('dumpster-%s-%s'):format(bucket, dumpsterId))

                if not dumpsterId then
                    dumpsterId = #registeredDumpsters + 1
                    registeredDumpsters[dumpsterId] = coords
                end

                if not right then
                    right = Inventory.Create(('dumpster-%s-%s'):format(bucket, dumpsterId), locale('dumpster'), invType, 15, 0,
                        100000, false)
                end

                right.coords = coords
                right.bucket = bucket
                right.instance = Player(source).state.instance
            else
                ---@cast data string
                if type(data) ~= 'string' or data:sub(1, 8) ~= 'dumpster' then return end

                local netid = tonumber(data:sub(9))
                local entity = netid and NetworkGetEntityFromNetworkId(netid) or 0

                if not isValidDumpsterEntity(entity) then return end

                local coords = GetEntityCoords(entity)

                if not ignoreSecurityChecks and #(GetEntityCoords(playerPed) - coords) > 10 then return end

                -- Canonicalise the numeric net id and isolate temporary dumpster
                -- inventories by routing bucket so separate dimensions cannot share loot.
                local bucket = GetPlayerRoutingBucket(source)
                local inventoryId = ('dumpster-%s-%s'):format(bucket, netid)
                right = Inventory(inventoryId)

                if not right then
                    right = Inventory.Create(inventoryId, locale('dumpster'), invType, 15, 0, 100000, false)
                end

                right.coords = coords
                right.bucket = bucket
                right.instance = Player(source).state.instance
            end
        elseif invType == 'container' then
            left.containerSlot = data --[[@as number]]
            data = left.items[data]

            if data then
                right = Inventory(data.metadata.container)

                if not right then
                    right = Inventory.Create(data.metadata.container, data.label, invType, data.metadata.size[1], 0,
                        data.metadata.size[2], false)
                end
            else
                left.containerSlot = nil
            end
        else
            right = Inventory(data)
        end

        if not right then return end

        -- Security check to make sure the requested inventory type is the same as the found inventory
        -- Only case where a missmatch is tolerated is for temporary stashes
        if right.type ~= invType and not (right.type == 'temp' and invType == 'stash') then
            Utils.LogExploit(source, 'openInventory', 'Attempted to open inventory with invalid inventory type.', true)
            return
        end

        if not ignoreSecurityChecks then
            local playerState = Player(source).state

            if right.groups and not server.hasGroup(left, right.groups) then return end
            if right.instance and playerState.instance ~= right.instance then return end
            if right.bucket ~= nil and GetPlayerRoutingBucket(source) ~= right.bucket then return end
        end

        local hookPayload = {
            source = source,
            inventoryId = right.id,
            inventoryType = right.type,
        }

        if invType == 'container' then hookPayload.slot = left.containerSlot end

        if isDataTable and data.netid then hookPayload.netId = data.netid end

        if left == right then return end

        if right.player then
            if right.open then return end

            right.coords = not ignoreSecurityChecks and GetEntityCoords(right.player.ped) or nil
        end

        if not ignoreSecurityChecks and right.coords then
            closestCoords = getClosestStashCoords(playerPed, right)

            if not closestCoords then return end
        end

        local hooks <close> = TriggerEventHooks('openInventory', hookPayload)

        if not hooks.success then return end
    end

    left:openInventory(right)

    return {
        id = left.id,
        label = left.label,
        type = left.type,
        slots = left.slots,
        weight = left.weight,
        maxWeight = left.maxWeight
    }, right and {
        id = right.id,
        label = right.player and '' or right.label,
        type = right.player and 'otherplayer' or right.type,
        slots = right.slots,
        weight = right.weight,
        maxWeight = right.maxWeight,
        items = right.items,
        coords = closestCoords or right.coords,
        distance = right.distance,
        instance = right.instance
    }
end

---@param source number
---@param invType string
---@param data string|number|table
lib.callback.register('ox_inventory:openInventory', function(source, invType, data)
    if invType == 'player' and source ~= data then
        local serverId = type(data) == 'table' and data.id or data

        if source == serverId or type(serverId) ~= 'number' then return end

        local left = Inventory(source)
        local right = Inventory(serverId)
        if not left or not right?.player then return end

        if #(GetEntityCoords(left.player.ped) - GetEntityCoords(right.player.ped)) > 3.0 then return end

        local isPolice = server.hasGroup(left, shared.police)
        local isTargetStealable = server.isPlayerSearchable(serverId)

        if not isPolice and not isTargetStealable then return end
        if GetPlayerRoutingBucket(source) ~= GetPlayerRoutingBucket(serverId) then return end
    end

    return openInventory(source, invType, data)
end)

---@param netId number
lib.callback.register('ox_inventory:isVehicleATrailer', function(source, netId)
    if type(netId) ~= 'number' or netId ~= netId or netId % 1 ~= 0 or netId <= 0 then return false end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end

    return GetVehicleType(entity) == 'trailer'
end)

---@param playerId number
---@param invType string
---@param data string|number|table
function server.forceOpenInventory(playerId, invType, data)
    local left, right = openInventory(playerId, invType, data, true)

    if left and right then
        TriggerClientEvent('ox_inventory:forceOpenInventory', playerId, left, right)
        return right.id
    end
end

exports('forceOpenInventory', server.forceOpenInventory)

local Licenses = lib.load('data.licenses')

lib.callback.register('ox_inventory:buyLicense', function(source, id)
    if type(id) ~= 'number' or id ~= id or id % 1 ~= 0 or id < 1 or id > 100000 then return end

    local license = Licenses[id]
    if not license or type(license.coords) ~= 'vector3' or type(license.name) ~= 'string'
        or type(license.price) ~= 'number' or license.price ~= license.price or license.price < 0 or license.price > 1000000000000 then return end

    local inventory = Inventory(source)
    if not inventory?.player then return end

    local ped = inventory.player.ped
    if not ped or ped == 0 or not DoesEntityExist(ped) or #(GetEntityCoords(ped) - license.coords) > 3.0 then return end

    local lockIds = {}
    for slot = 1, inventory.slots do
        lockIds[slot] = ('inventory-%s:slot-%s'):format(inventory.id, slot)
    end

    local activeSlots <close> = GetLocks(lockIds)
    if not activeSlots or Inventory(source) ~= inventory then return end
    if #(GetEntityCoords(ped) - license.coords) > 3.0 then return end

    return server.buyLicense(inventory, license)
end)

---@param source number
---@param id? string | number
---@return OxInventory?
local function getClientAccessibleInventory(source, id)
    local playerInventory = Inventory(source)
    if not playerInventory then return end

    if id ~= nil then
        if type(id) ~= 'string' and type(id) ~= 'number' then return end
        if id ~= source and id ~= playerInventory.id and id ~= playerInventory.open then return end
    end

    local inventory = Inventory(id or source)
    if not inventory then return end

    -- Client callbacks may inspect the player's own inventory or the secondary
    -- inventory the server already authorised and opened.
    if inventory ~= playerInventory and playerInventory.open ~= inventory.id then return end

    return inventory
end

lib.callback.register('ox_inventory:getItemCount', function(source, item, metadata, target)
    if type(item) ~= 'string' or (metadata ~= nil and type(metadata) ~= 'table' and type(metadata) ~= 'string') then return 0 end

    local inventory = getClientAccessibleInventory(source, target)
    return (inventory and Inventory.GetItemCount(inventory, item, metadata, true))
end)

lib.callback.register('ox_inventory:getInventory', function(source, id)
    local inventory = getClientAccessibleInventory(source, id)
    return inventory and {
        id = inventory.id,
        label = inventory.label,
        type = inventory.type,
        slots = inventory.slots,
        weight = inventory.weight,
        maxWeight = inventory.maxWeight,
        owned = inventory.owner and true or false,
        items = inventory.items
    }
end)

RegisterNetEvent('ox_inventory:usedItemInternal', function(slot)
    if type(slot) ~= 'number' or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > 100000 then return end

    local inventory = Inventory(source)

    if not inventory then return end

    local item = inventory.usingItem

    if not item or item.slot ~= slot then
        Utils.LogExploit(inventory.id, 'usedItemInternal', 'Triggered internal event.', true)
        return
    end

    TriggerEvent('ox_inventory:usedItem', inventory.id, item.name, item.slot, next(item.metadata) and item.metadata)

    inventory.usingItem = nil
end)


---@param source number
---@param itemName string
---@param slot number?
---@param metadata { [string]: any }?
---@return table | boolean | nil
lib.callback.register('ox_inventory:useItem', function(source, itemName, slot, metadata, noAnim)
    if type(itemName) ~= 'string'
        or (slot ~= nil and (type(slot) ~= 'number' or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > 100000))
        or (metadata ~= nil and type(metadata) ~= 'table')
        or (noAnim ~= nil and type(noAnim) ~= 'boolean') then
        Utils.LogExploit(source, 'useItem', 'Triggered callback with malformed data', true)
        return
    end

    local inventory = Inventory(source)

    if inventory and inventory.player then
        local item = Items(itemName)
        local data = item and
        (slot and inventory.items[slot] or Inventory.GetSlotWithItem(inventory, item.name, metadata, true))

        if not data then return end

        slot = data.slot
        local durability = data.metadata.durability --[[@as number|boolean|nil]]
        local consume = item.consume
        local label = data.metadata.label or item.label

        if durability and consume then
            if durability > 100 then
                local ostime = os.time()

                if ostime > durability then
                    Items.UpdateDurability(inventory, data, item, 0)
                    return TriggerClientEvent('ox_lib:notify', source,
                        { type = 'error', description = locale('no_durability', label) })
                elseif consume ~= 0 and consume < 1 then
                    local degrade = (data.metadata.degrade or item.degrade) * 60
                    local percentage = ((durability - ostime) * 100) / degrade

                    if percentage < consume * 100 then
                        return TriggerClientEvent('ox_lib:notify', source,
                            { type = 'error', description = locale('not_enough_durability', label) })
                    end
                end
            elseif durability <= 0 then
                return TriggerClientEvent('ox_lib:notify', source,
                    { type = 'error', description = locale('no_durability', label) })
            elseif consume ~= 0 and consume < 1 and durability < consume * 100 then
                return TriggerClientEvent('ox_lib:notify', source,
                    { type = 'error', description = locale('not_enough_durability', label) })
            end

            if data.count > 1 and consume < 1 and consume > 0 and not Inventory.GetEmptySlot(inventory) then
                return TriggerClientEvent('ox_lib:notify', source,
                    { type = 'error', description = locale('cannot_use', label) })
            end
        end

        if item and data and data.count > 0 and data.name == item.name then
            local activeSlots <close> = GetLocks({
                ('inventory-%s:slot-%s'):format(inventory.id, slot),
            })

    		if not activeSlots then return end

            data = { name = data.name, label = label, count = data.count, slot = slot, metadata = data.metadata, weight =
            data.weight }

            if item.ammo then
                if inventory.weapon then
                    local weapon = inventory.items[inventory.weapon]

                    if weapon and weapon?.metadata.durability > 0 then
                        consume = nil
                    end
                else
                    return false
                end
            elseif item.component or item.tint then
                consume = 1
                data.component = true
            elseif consume then
                if data.count >= consume then
                    local result = item.cb and item.cb('usingItem', item, inventory, slot)

                    if result == false then return end

                    if result ~= nil then
                        data.server = result
                    end
                else
                    return TriggerClientEvent('ox_lib:notify', source,
                        { type = 'error', description = locale('item_not_enough', item.name) })
                end
            elseif not item.weapon and server.UseItem then
                inventory.usingItem = data
                -- This is used to call an external useItem function, i.e. ESX.UseItem
                -- If an error is being thrown on item use there is no internal solution. We previously kept a list
                -- of usable items which led to issues when restarting resources (for obvious reasons), but config
                -- developers complained the inventory broke their items. Safely invoking registered item callbacks
                -- should resolve issues, i.e. https://github.com/esx-framework/esx-legacy/commit/9fc382bbe0f5b96ff102dace73c424a53458c96e
                return pcall(server.UseItem, source, data.name, data)
            end

            data.consume = consume

            local hooks <close> = TriggerEventHooks('usingItem', {
                source = source,
                inventoryId = inventory and inventory.id,
                item = inventory.items[slot],
                consume = consume
            })

            if not hooks.success then return false end

            local callbackOk, success = pcall(lib.callback.await, 'ox_inventory:usingItem', source, data, noAnim)

            if not callbackOk then
                hooks.success = false
                return
            end

            -- A numeric source id can be recycled while the client callback is waiting.
            -- Never commit against a new session that inherited the old source id.
            if Inventory(source) ~= inventory then
                hooks.success = false
                return
            end

            if item.weapon then
                inventory.weapon = success and slot or nil
            end

            if not success then hooks.success = false return end
            if Inventory(source) ~= inventory then hooks.success = false return end

            inventory.usingItem = data

            if consume and consume ~= 0 and not data.component then
                data = inventory.items[data.slot]

                if not data then hooks.success = false return end

                durability = consume ~= 0 and consume < 1 and data.metadata.durability --[[@as number | false]]

                if durability then
                    if durability > 100 then
                        local degrade = (data.metadata.degrade or item.degrade) * 60
                        durability -= degrade * consume
                    else
                        durability -= consume * 100
                    end

                    if data.count > 1 then
                        local emptySlot = Inventory.GetEmptySlot(inventory)

                        if emptySlot then
                            local ok, newItem = Inventory.SetSlot(inventory, item, 1, table.deepclone(data.metadata),
                                emptySlot)

                            if ok and newItem then
                                Items.UpdateDurability(inventory, newItem --[[@as SlotWithItem]], item, durability)
                            end
                        end

                        durability = 0
                    else
                        Items.UpdateDurability(inventory, data, item, durability)
                    end

                    if durability <= 0 then
                        durability = false
                    end
                end

                if not durability then
                    Inventory.RemoveItem(inventory.id, data.name, consume < 1 and 1 or consume, nil, data.slot)
                else
                    inventory.changed = true

                    if server.syncInventory then server.syncInventory(inventory) end
                end

                if item?.cb then
                    item.cb('usedItem', item, inventory, data.slot)
                end
            end

            return true
        end
    end
end)

local function conversionScript()
    shared.ready = false

    local file = 'setup/convert.lua'
    local import = LoadResourceFile(shared.resource, file)
    local func = load(import, ('@@%s/%s'):format(shared.resource, file)) --[[@as function]]

    conversionScript = func()
end

RegisterCommand('convertinventory', function(source, args)
    if source ~= 0 then return warn('This command can only be executed with the server console.') end
    if type(conversionScript) == 'function' then conversionScript() end
    local arg = args[1]

    local convert = arg and conversionScript[arg]

    if not convert then
        return warn('Invalid conversion argument. Valid options: esx, esxproperty')
    end

    CreateThread(convert)
end, true)


lib.addCommand({ 'additem', 'giveitem' }, {
    help = 'Gives an item to a player with the given id',
    params = {
        { name = 'target', type = 'playerId',                              help = 'The player to receive the item' },
        { name = 'item',   type = 'string',                                help = 'The name of the item' },
        { name = 'count',  type = 'number',                                help = 'The amount of the item to give', optional = true },
        { name = 'type',   help = 'Sets the "type" metadata to the value', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local item = Items(args.item)

    if item then
        local inventory = Inventory(args.target) --[[@as OxInventory]]
        local count = args.count and math.max(args.count, 1) or 1

        local success, response = Inventory.AddItem(inventory, item.name, count,
            args.type and { type = tonumber(args.type) or args.type })

        if not success then
            return Citizen.Trace(('Failed to give %sx %s to player %s (%s)'):format(count, item.name, args.target,
                response))
        end

        source = Inventory(source) or { label = 'console', owner = 'console' }

        if server.loglevel > 0 then
            lib.logger(source.owner, 'admin',
                ('"%s" gave %sx %s to "%s"'):format(source.label, count, item.name, inventory.label))
        end
    end
end)

lib.addCommand('removeitem', {
    help = 'Removes an item to a player with the given id',
    params = {
        { name = 'target', type = 'playerId',                                          help = 'The player to remove the item from' },
        { name = 'item',   type = 'string',                                            help = 'The name of the item' },
        { name = 'count',  type = 'number',                                            help = 'The amount of the item to take',    optional = true },
        { name = 'type',   help = 'Only remove items with a matching metadata "type"', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local item = Items(args.item)

    if item then
        local inventory = Inventory(args.target) --[[@as OxInventory]]
        local count = args.count and math.max(args.count, 1) or 1

        local success, response = Inventory.RemoveItem(inventory, item.name, count,
            args.type and { type = tonumber(args.type) or args.type }, nil, true)

        if not success then
            return Citizen.Trace(('Failed to remove %sx %s from player %s (%s)'):format(count, item.name, args.target,
                response))
        end

        source = Inventory(source) or { label = 'console', owner = 'console' }

        if server.loglevel > 0 then
            lib.logger(source.owner, 'admin',
                ('"%s" removed %sx %s from "%s"'):format(source.label, count, item.name, inventory.label))
        end
    end
end)

lib.addCommand('setitem', {
    help = 'Sets the item count for a player, removing or adding as needed',
    params = {
        { name = 'target', type = 'playerId',                                     help = 'The player to set the items for' },
        { name = 'item',   type = 'string',                                       help = 'The name of the item' },
        { name = 'count',  type = 'number',                                       help = 'The amount of items to set',     optional = true },
        { name = 'type',   help = 'Add or remove items with the metadata "type"', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local item = Items(args.item)

    if item then
        local inventory = Inventory(args.target) --[[@as OxInventory]]
        local count = args.count and math.max(args.count, 0) or 0

        local success, response = Inventory.SetItem(inventory, item.name, count or 0,
            args.type and { type = tonumber(args.type) or args.type })

        if not success then
            return Citizen.Trace(('Failed to set %s count to %sx for player %s (%s)'):format(item.name, count,
                args.target, response))
        end

        source = Inventory(source) or { label = 'console', owner = 'console' }

        if server.loglevel > 0 then
            lib.logger(source.owner, 'admin',
                ('"%s" set "%s" %s count to %sx'):format(source.label, inventory.label, item.name, count))
        end
    end
end)

lib.addCommand('clearevidence', {
    help = 'Clears a police evidence locker with the given id',
    params = {
        { name = 'locker', type = 'number', help = 'The locker id to clear' },
    },
}, function(source, args)
    if not server.isPlayerBoss then return end

    local inventory = Inventory(source)
    if not inventory then return end

    local group, grade = server.hasGroup(inventory, shared.police)
    local hasPermission = group and server.isPlayerBoss(source, group, grade)

    if hasPermission then
        MySQL.query('DELETE FROM ox_inventory WHERE name = ?', { ('evidence-%s'):format(args.locker) })
    end
end)

lib.addCommand('takeinv', {
    help = 'Confiscates the target inventory, to restore with /restoreinv',
    params = {
        { name = 'target', type = 'playerId', help = 'The player to confiscate items from' },
    },
    restricted = 'group.admin',
}, function(source, args)
    Inventory.Confiscate(args.target)
end)

lib.addCommand({ 'restoreinv', 'returninv' }, {
    help = 'Restores a previously confiscated inventory for the target',
    params = {
        { name = 'target', type = 'playerId', help = 'The player to restore items to' },
    },
    restricted = 'group.admin',
}, function(source, args)
    Inventory.Return(args.target)
end)

lib.addCommand('clearinv', {
    help = 'Wipes all items from the target inventory',
    params = {
        { name = 'invId', help = 'The inventory to wipe items from' },
    },
    restricted = 'group.admin',
}, function(source, args)
    Inventory.Clear(tonumber(args.invId) or args.invId == 'me' and source or args.invId)
end)

lib.addCommand('saveinv', {
    help = 'Save all pending inventory changes to the database',
    params = {
        { name = 'lock', help = 'Lock inventory access, until restart or saved without a lock', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    Inventory.SaveInventories(args.lock == 'true', false)
end)

lib.addCommand('viewinv', {
    help = 'Inspect the target inventory without allowing interactions',
    params = {
        { name = 'invId', help = 'The inventory to inspect' },
    },
    restricted = 'group.admin',
}, function(source, args)
    Inventory.InspectInventory(source, tonumber(args.invId) or args.invId)
end)

lib.registerHook('ox_lib:setPlayerState', nil, {
    key = 'invBusy'
})

lib.registerHook('ox_lib:setPlayerState', nil, {
    key = 'canSteal'
})

if not lib then return end

local Query = {
    SELECT_STASH = 'SELECT data FROM ox_inventory WHERE owner = ? AND name = ?',
    UPDATE_STASH = 'UPDATE ox_inventory SET data = ? WHERE owner = ? AND name = ?',
    UPSERT_STASH =
    'INSERT INTO ox_inventory (data, owner, name) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
    INSERT_STASH = 'INSERT INTO ox_inventory (owner, name) VALUES (?, ?)',
    DELETE_STASH = 'DELETE FROM ox_inventory WHERE owner = ? AND name = ?',
    SELECT_GLOVEBOX = 'SELECT plate, glovebox FROM `{vehicle_table}` WHERE `{vehicle_column}` = ?',
    SELECT_TRUNK = 'SELECT plate, trunk FROM `{vehicle_table}` WHERE `{vehicle_column}` = ?',
    SELECT_PLAYER = 'SELECT inventory FROM `{user_table}` WHERE `{user_column}` = ?',
    UPDATE_TRUNK = 'UPDATE `{vehicle_table}` SET trunk = ? WHERE `{vehicle_column}` = ?',
    UPDATE_GLOVEBOX = 'UPDATE `{vehicle_table}` SET glovebox = ? WHERE `{vehicle_column}` = ?',
    UPDATE_PLAYER = 'UPDATE `{user_table}` SET inventory = ? WHERE `{user_column}` = ?',
}

Citizen.CreateThreadNow(function()
    local playerTable, playerColumn, vehicleTable, vehicleColumn

    if shared.framework == 'ox' then
        playerTable = 'character_inventory'
        playerColumn = 'charid'
        vehicleTable = 'vehicles'
        vehicleColumn = 'id'
    elseif shared.framework == 'esx' then
        playerTable = 'users'
        playerColumn = 'identifier'
        vehicleTable = 'owned_vehicles'
        vehicleColumn = 'plate'
    elseif shared.framework == 'nd' then
        playerTable = 'nd_characters'
        playerColumn = 'charid'
        vehicleTable = 'nd_vehicles'
        vehicleColumn = 'id'
    elseif shared.framework == 'qbx' then
        playerTable = 'players'
        playerColumn = 'citizenid'
        vehicleTable = 'player_vehicles'
        vehicleColumn = 'id'
    else
        return
    end

    for k, v in pairs(Query) do
        Query[k] = v:gsub('{user_table}', playerTable):gsub('{user_column}', playerColumn):gsub('{vehicle_table}',
            vehicleTable):gsub('{vehicle_column}', vehicleColumn)
    end

    Wait(0)

    -- Never interpret a connection/query failure as "schema missing". Doing so can
    -- turn a temporary database outage into a cascade of CREATE/ALTER attempts.
    local ok, tables = pcall(MySQL.query.await, "SHOW TABLES LIKE 'ox_inventory'")
    if not ok then
        warn(('Unable to inspect ox_inventory schema; skipping automatic migrations: %s'):format(tostring(tables)))
        return
    end

    if not tables or #tables == 0 then
        local createOk, createErr = pcall(MySQL.query.await, [[CREATE TABLE `ox_inventory` (
            `owner` varchar(60) DEFAULT NULL,
            `name` varchar(100) NOT NULL,
            `data` longtext DEFAULT NULL,
            `lastupdated` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            UNIQUE KEY `owner` (`owner`,`name`)
        )]])
        if not createOk then
            warn(('Failed to create ox_inventory table: %s'):format(tostring(createErr)))
            return
        end
    end

    local vehicleOk, vehicleColumns = pcall(MySQL.query.await, ('SHOW COLUMNS FROM `%s`'):format(vehicleTable))
    if not vehicleOk then
        warn(('Unable to inspect vehicle inventory columns on %s; skipping vehicle schema migration: %s'):format(vehicleTable, tostring(vehicleColumns)))
    elseif vehicleColumns then
        local glovebox, trunk
        for i = 1, #vehicleColumns do
            local column = vehicleColumns[i]
            if column.Field == 'glovebox' then
                glovebox = true
            elseif column.Field == 'trunk' then
                trunk = true
            end
        end

        if not glovebox then
            local alterOk, alterErr = pcall(MySQL.query.await, ('ALTER TABLE `%s` ADD COLUMN `glovebox` LONGTEXT NULL'):format(vehicleTable))
            if not alterOk then warn(('Failed to add glovebox column to %s: %s'):format(vehicleTable, tostring(alterErr))) end
        end
        if not trunk then
            local alterOk, alterErr = pcall(MySQL.query.await, ('ALTER TABLE `%s` ADD COLUMN `trunk` LONGTEXT NULL'):format(vehicleTable))
            if not alterOk then warn(('Failed to add trunk column to %s: %s'):format(vehicleTable, tostring(alterErr))) end
        end
    end

    local playerOk, playerColumns = pcall(MySQL.query.await, ('SHOW COLUMNS FROM `%s`'):format(playerTable))
    if not playerOk then
        warn(('Unable to inspect player inventory column on %s; skipping player schema migration: %s'):format(playerTable, tostring(playerColumns)))
    elseif playerColumns then
        local inventoryColumn
        for i = 1, #playerColumns do
            if playerColumns[i].Field == 'inventory' then inventoryColumn = true break end
        end

        if not inventoryColumn then
            local alterOk, alterErr = pcall(MySQL.query.await, ('ALTER TABLE `%s` ADD COLUMN `inventory` LONGTEXT NULL'):format(playerTable))
            if not alterOk then warn(('Failed to add inventory column to %s: %s'):format(playerTable, tostring(alterErr))) end
        end
    end

    local clearStashes = GetConvar('inventory:clearstashes', '6 MONTH')
    if clearStashes ~= '' then
        local clearOk, clearErr = pcall(MySQL.query.await, ('DELETE FROM ox_inventory WHERE lastupdated < (NOW() - INTERVAL %s)'):format(clearStashes))
        if not clearOk then warn(('Failed to clear expired stashes: %s'):format(tostring(clearErr))) end
    end
end)


db = {}

---@param fn function
---@param ... any
---@return any result
---@return string? errorMessage
local function safeAwait(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        return nil, tostring(result)
    end

    return result
end

function db.loadPlayer(identifier)
    local inventory, err = safeAwait(MySQL.prepare.await, Query.SELECT_PLAYER, { identifier }) --[[@as string?]]

    if err then return nil, err end
    if not inventory then return nil end

    local ok, decoded = pcall(json.decode, inventory)
    if not ok then return nil, tostring(decoded) end

    return decoded
end

function db.savePlayer(owner, inventory)
    return MySQL.prepare.await(Query.UPDATE_PLAYER, { inventory, owner })
end

function db.saveStash(owner, dbId, inventory)
    return MySQL.prepare.await(Query.UPSERT_STASH, { inventory, owner and tostring(owner) or '', dbId })
end

function db.loadStash(owner, name)
    return safeAwait(MySQL.prepare.await, Query.SELECT_STASH, { owner and tostring(owner) or '', name })
end

-- Confiscation is a durable move, not two unrelated writes. Persist the recovery
-- snapshot and clear the player's stored inventory in one database transaction so
-- a process crash cannot leave both copies durable at once.
function db.confiscatePlayer(owner, recoveryName, inventory)
    return safeAwait(MySQL.transaction.await, {
        { query = Query.UPSERT_STASH, values = { inventory, tostring(owner), recoveryName } },
        { query = Query.UPDATE_PLAYER, values = { '[]', owner } },
    })
end

-- Restoration is the inverse durable move. The recovery row is only deleted if
-- the merged player inventory is persisted successfully in the same transaction.
function db.returnConfiscatedPlayer(owner, recoveryName, inventory)
    return safeAwait(MySQL.transaction.await, {
        { query = Query.UPDATE_PLAYER, values = { inventory or '[]', owner } },
        { query = Query.DELETE_STASH, values = { tostring(owner), recoveryName } },
    })
end

function db.saveGlovebox(id, inventory)
    return MySQL.prepare.await(Query.UPDATE_GLOVEBOX, { inventory, id })
end

function db.loadGlovebox(id)
    return safeAwait(MySQL.prepare.await, Query.SELECT_GLOVEBOX, { id })
end

function db.saveTrunk(id, inventory)
    return MySQL.prepare.await(Query.UPDATE_TRUNK, { inventory, id })
end

function db.loadTrunk(id)
    return safeAwait(MySQL.prepare.await, Query.SELECT_TRUNK, { id })
end

---@param rows number | MySQLQuery | MySQLQuery[]
local function countRows(rows)
    if type(rows) == 'number' then return rows end

    local n = 0

    for i = 1, #rows do
        if rows[i] == 1 then n += 1 end
    end

    return n
end

local function safeQuery(...)
    local ok, resp = pcall(...)

    if not ok then
        warn(resp)
        return nil, tostring(resp)
    end

    return resp
end

---@param players InventorySaveData[]
---@param trunks InventorySaveData[]
---@param gloveboxes InventorySaveData[]
---@param stashes (InventorySaveData | string | number)[]
---@param total number[]
function db.saveInventories(players, trunks, gloveboxes, stashes, total)
    local start = os.nanotime()
    local saveStr = 'Saved %d/%d %s (%.4f ms)'
    local pending = 0
    local results = { true, true, true, true }

    shared.info(('Saving %s inventories to the database'):format(total[5]))

    if total[1] > 0 then
        pending += 1

        Citizen.CreateThreadNow(function()
            local resp = safeQuery(MySQL.prepare.await, Query.UPDATE_PLAYER, players)
            results[1] = resp ~= nil
            pending -= 1

            if resp then
                shared.info(saveStr:format(countRows(resp), total[1], 'players', (os.nanotime() - start) / 1e6))
            end
        end)
    end

    if total[2] > 0 then
        pending += 1

        Citizen.CreateThreadNow(function()
            local resp = safeQuery(MySQL.prepare.await, Query.UPDATE_TRUNK, trunks)
            results[2] = resp ~= nil
            pending -= 1

            if resp then
                shared.info(saveStr:format(countRows(resp), total[2], 'trunks', (os.nanotime() - start) / 1e6))
            end
        end)
    end

    if total[3] > 0 then
        pending += 1

        Citizen.CreateThreadNow(function()
            local resp = safeQuery(MySQL.prepare.await, Query.UPDATE_GLOVEBOX, gloveboxes)
            results[3] = resp ~= nil
            pending -= 1

            if resp then
                shared.info(saveStr:format(countRows(resp), total[3], 'gloveboxes', (os.nanotime() - start) / 1e6))
            end
        end)
    end

    if total[4] > 0 then
        pending += 1

        if server.bulkstashsave then
            total[4] /= 3

            Citizen.CreateThreadNow(function()
                local query = Query.UPSERT_STASH:gsub('%(%?, %?, %?%)', string.rep('(?, ?, ?)', total[4], ', '))
                local resp = safeQuery(MySQL.query.await, query, stashes)
                results[4] = resp ~= nil
                pending -= 1

                if resp then
                    local affectedRows = resp.affectedRows

                    if total[4] == 1 then
                        if affectedRows == 2 then affectedRows = 1 end
                    else
                        affectedRows -= tonumber(resp.info:match('Duplicates: (%d+)'), 10) or 0
                    end

                    shared.info(saveStr:format(affectedRows, total[4], 'stashes', (os.nanotime() - start) / 1e6))
                end
            end)
        else
            Citizen.CreateThreadNow(function()
                local resp = safeQuery(MySQL.rawExecute.await, Query.UPSERT_STASH, stashes)
                results[4] = resp ~= nil
                pending -= 1

                if resp then
                    local affectedRows = 0

                    if table.type(resp) == 'hash' then
                        if resp.affectedRows > 0 then affectedRows = 1 end
                    else
                        for i = 1, #resp do
                            if resp[i].affectedRows > 0 then affectedRows += 1 end
                        end
                    end

                    shared.info(saveStr:format(affectedRows, total[4], 'stashes', (os.nanotime() - start) / 1e6))
                end
            end)
        end
    end

    repeat Wait(0) until pending == 0
    return results
end

return db

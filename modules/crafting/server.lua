if not lib then return end

local CraftingBenches = {}
local Items = require 'modules.items.server'
local Inventory = require 'modules.inventory.server'

---@param id number | string
---@param data table
local function createCraftingBench(id, data)
	CraftingBenches[id] = {}
	local recipes = data.items

	if recipes then
		for i = 1, #recipes do
			local recipe = recipes[i]
			local item = Items(recipe.name)

			if item then
				recipe.weight = item.weight
				recipe.slot = i
			else
				warn(('failed to setup crafting recipe (bench: %s, slot: %s) - item "%s" does not exist'):format(id, i, recipe.name))
			end

			for ingredient, needs in pairs(recipe.ingredients) do
				if needs < 1 then
					item = Items(ingredient)

					if item and not item.durability then
						item.durability = true
					end
				end
			end
		end

		if shared.target then
			data.points = nil
		else
			data.zones = nil
		end

		CraftingBenches[id] = data
	end
end

for id, data in pairs(lib.load('data.crafting') or {}) do createCraftingBench(data.name or id, data) end

---@param bench table
---@param index number
---@return table?
local function getCraftingGroups(bench, index)
	return (shared.target and bench.zones) and bench.zones[index]?.groups or bench.groups
end

---falls back to player coords if zones and points are both nil
---@param source number
---@param bench table
---@param index number
---@return vector3
local function getCraftingCoords(source, bench, index)
	if not bench.zones and not bench.points then
		return GetEntityCoords(GetPlayerPed(source))
	else
		return shared.target and bench.zones[index]?.coords or bench.points?[index]
	end
end

lib.callback.register('ox_inventory:openCraftingBench', function(source, id, index)
	local left, bench = Inventory(source), CraftingBenches[id]

	if not left then return end

	if bench then
		local groups = getCraftingGroups(bench, index)
		local coords = getCraftingCoords(source, bench, index)

		if not coords then return end

		if groups and not server.hasGroup(left, groups) then return end

		local distance = 2.0
		if shared.target and bench.zones and bench.zones[index] then
			distance = bench.zones[index].distance or distance
		end
		if #(GetEntityCoords(GetPlayerPed(source)) - coords) > math.max(distance + 1.0, 3.0) then return end

		if left.open and left.open ~= source then
			local inv = Inventory(left.open) --[[@as OxInventory]]

			-- Why would the player inventory open with an invalid target? Can't repro but whatever.
			if inv?.player then
				inv:closeInventory()
			end
		end

		left:openInventory()
	end

	return { label = left.label, type = left.type, slots = left.slots, weight = left.weight, maxWeight = left.maxWeight }
end)

local TriggerEventHooks = require 'modules.hooks.server'
local GetLocks = require 'modules.locks'

---@param value any
---@return boolean
local function isPositiveInteger(value)
	return type(value) == 'number' and value == value and value % 1 == 0 and value > 0 and value <= 100000
end

---@param source number
---@param bench table
---@param index number?
---@return boolean
local function canAccessBench(source, bench, index)
	local left = Inventory(source)
	if not left then return false end

	local groups = getCraftingGroups(bench, index)
	if groups and not server.hasGroup(left, groups) then return false end

	local coords = getCraftingCoords(source, bench, index)
	if not coords then return false end

	local ped = GetPlayerPed(source)
	if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

	local distance = 2.0
	if shared.target and bench.zones and bench.zones[index] then
		distance = bench.zones[index].distance or distance
	end

	return #(GetEntityCoords(ped) - coords) <= math.max(distance + 1.0, 3.0)
end

---@param inv OxInventory
---@param recipe table
---@return table<number, {slot: number, amount: number, name: string}>?
local function buildIngredientPlan(inv, recipe)
	local plan = {}

	for name, configuredNeeds in pairs(recipe.ingredients) do
		if type(name) ~= 'string' or type(configuredNeeds) ~= 'number' or configuredNeeds ~= configuredNeeds or configuredNeeds < 0 then
			return
		end

		local matching = {}
		for slot, slotData in pairs(inv.items) do
			if slotData.name == name then matching[#matching + 1] = slotData end
		end
		table.sort(matching, function(a, b) return a.slot < b.slot end)

		if configuredNeeds == 0 then
			local found
			for i = 1, #matching do
				local slotData = matching[i]
				if not slotData.metadata.durability or slotData.metadata.durability > 0 then
					found = slotData
					break
				end
			end
			if not found then return end
			plan[#plan + 1] = { slot = found.slot, amount = 0, name = name }
		elseif configuredNeeds < 1 then
			local found
			local item = Items(name)
			for i = 1, #matching do
				local slotData = matching[i]
				local durability = slotData.metadata.durability
				if durability and durability >= configuredNeeds * 100 then
					if durability > 100 then
						local degrade = (slotData.metadata.degrade or item.degrade) * 60
						local percentage = degrade > 0 and ((durability - os.time()) * 100) / degrade or 0
						if percentage >= configuredNeeds * 100 then found = slotData break end
					else
						found = slotData
						break
					end
				end
			end
			if not found then return end
			plan[#plan + 1] = { slot = found.slot, amount = configuredNeeds, name = name }
		else
			if configuredNeeds % 1 ~= 0 then return end
			local remaining = configuredNeeds
			for i = 1, #matching do
				local slotData = matching[i]
				local take = math.min(remaining, slotData.count)
				if take > 0 then
					plan[#plan + 1] = { slot = slotData.slot, amount = take, name = name }
					remaining -= take
				end
				if remaining == 0 then break end
			end
			if remaining > 0 then return end
		end
	end

	return plan
end

---@param inv OxInventory
---@param snapshotItems table
---@param snapshotWeight number
---@param snapshotChanged boolean?
---@param snapshotWeapon number?
local function restoreCraftSnapshot(inv, snapshotItems, snapshotWeight, snapshotChanged, snapshotWeapon)
	inv.items = snapshotItems
	inv.weight = snapshotWeight
	inv.changed = snapshotChanged
	inv.weapon = snapshotWeapon

	local updates = {}
	for slot = 1, inv.slots do
		updates[#updates + 1] = {
			item = inv.items[slot] or { slot = slot },
			inventory = inv.id
		}
	end
	inv:syncSlotsWithClients(updates, true)
	if server.syncInventory then server.syncInventory(inv) end
end

lib.callback.register('ox_inventory:craftItem', function(source, id, index, recipeId, toSlot)
	if not isPositiveInteger(recipeId) or not isPositiveInteger(toSlot) then return end
	if index ~= nil and (type(index) ~= 'number' or index ~= index or index % 1 ~= 0 or index < 1 or index > 100000) then return end
	if type(id) ~= 'string' and type(id) ~= 'number' then return end

	local left, bench = Inventory(source), CraftingBenches[id]
	if not left or not bench or not canAccessBench(source, bench, index) then return end
	if toSlot > left.slots then return end

	local recipe = bench.items and bench.items[recipeId]
	if not recipe then return end

	local craftedItem = Items(recipe.name)
	if not craftedItem or type(recipe.ingredients) ~= 'table' then return end

	local craftCount
	if type(recipe.count) == 'number' then
		craftCount = math.floor(recipe.count)
	elseif table.type(recipe.count) == 'array' and type(recipe.count[1]) == 'number' and type(recipe.count[2]) == 'number' then
		local minimum, maximum = math.floor(recipe.count[1]), math.floor(recipe.count[2])
		if minimum > maximum then minimum, maximum = maximum, minimum end
		craftCount = math.random(minimum, maximum)
	else
		craftCount = 1
	end
	if craftCount < 1 or craftCount > 100000 then return end

	-- Lock every currently matching ingredient slot plus the requested destination.
	-- This avoids selecting an unlocked replacement ingredient after waiting on a lock.
	local lockIds, seenLocks = {}, {}
	local function addLock(slot)
		local key = ('inventory-%s:slot-%s'):format(left.id, slot)
		if not seenLocks[key] then
			seenLocks[key] = true
			lockIds[#lockIds + 1] = key
		end
	end
	-- Crafting is one inventory transaction. Lock the full player inventory for the
	-- progress window so empty-slot splits and output placement cannot race other actions.
	for slot = 1, left.slots do addLock(slot) end

	local activeSlots <close> = GetLocks(lockIds)
	if not activeSlots then return end
	if Inventory(source) ~= left or not canAccessBench(source, bench, index) then return end

	local ingredientPlan = buildIngredientPlan(left, recipe)
	if not ingredientPlan then return end

	local hooks <close> = TriggerEventHooks('craftItem', {
		source = source,
		benchId = id,
		benchIndex = index,
		recipe = recipe,
		toInventory = left.id,
		toSlot = toSlot,
	})
	if not hooks.success then return false end
	if Inventory(source) ~= left then hooks.success = false return end

	local duration = tonumber(recipe.duration) or 3000
	duration = math.max(0, math.floor(duration))
	local startedAt = GetGameTimer()
	local callbackOk, success = pcall(lib.callback.await, 'ox_inventory:startCrafting', source, id, recipeId)

	if not callbackOk or not success then hooks.success = false return false end
	if Inventory(source) ~= left or not canAccessBench(source, bench, index) then hooks.success = false return false end
	if GetGameTimer() - startedAt + 150 < duration then
		hooks.success = false
		return false
	end

	-- Rebuild under the locks so ingredient counts/durability are current at commit time.
	ingredientPlan = buildIngredientPlan(left, recipe)
	if not ingredientPlan then hooks.success = false return false end

	local snapshotItems = table.deepclone(left.items)
	local snapshotWeight = left.weight
	local snapshotChanged = left.changed
	local snapshotWeapon = left.weapon

	local committed, commitError = xpcall(function()
		for i = 1, #ingredientPlan do
			local step = ingredientPlan[i]
			local invSlot = left.items[step.slot]
			if not invSlot or invSlot.name ~= step.name then error('craft ingredient changed during commit') end

			if step.amount == 0 then
				-- Required tool/item: presence only, no consumption or durability loss.
			elseif step.amount < 1 then
				local item = Items(invSlot.name)
				local durability = invSlot.metadata.durability
				if not durability then error('craft durability ingredient missing durability') end

				if durability > 100 then
					local degrade = (invSlot.metadata.degrade or item.degrade) * 60
					durability -= degrade * step.amount
				else
					durability -= step.amount * 100
				end

				if invSlot.count > 1 then
					local emptySlot = Inventory.GetEmptySlot(left)
					if not emptySlot then error('craft durability split requires empty slot') end
					local ok, newItem = Inventory.SetSlot(left, item, 1, table.deepclone(invSlot.metadata), emptySlot)
					if not ok or not newItem then error('craft durability split failed') end
					Items.UpdateDurability(left, newItem, item, math.max(durability, 0))
					invSlot.count -= 1
					invSlot.weight = Inventory.SlotWeight(item, invSlot)
					left.weight = Inventory.CalculateWeight(left.items)
					left.changed = true
					left:syncSlotsWithClients({ { item = invSlot, inventory = left.id } }, true)
				else
					Items.UpdateDurability(left, invSlot, item, math.max(durability, 0))
				end
			else
				local removed = Inventory.RemoveItem(left, invSlot.name, step.amount, nil, step.slot)
				if not removed then error('craft ingredient removal failed') end
			end
		end

		if Inventory(source) ~= left or not canAccessBench(source, bench, index) then
			error('craft session changed before output')
		end

		local added = Inventory.AddItem(left, craftedItem, craftCount, recipe.metadata or {}, craftedItem.stack and toSlot or nil)
		if not added then error('craft output insertion failed') end
		if left.weight > left.maxWeight then error('craft output exceeds inventory weight') end
	end, debug.traceback)

	if not committed then
		hooks.success = false
		restoreCraftSnapshot(left, snapshotItems, snapshotWeight, snapshotChanged, snapshotWeapon)
		lib.print.error(('Craft transaction rolled back for player %s: %s'):format(source, tostring(commitError)))
		return false, 'cannot_perform'
	end

	return true
end)

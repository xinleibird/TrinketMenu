--[[ TrinketMenuQueue : auto queue system ]]

-- SavedVariable
-- Sort[which][scope]         : 4 independent trinket sort lists
-- Enabled[which]             : master toggle per slot (1D)
-- ScopeEnabled[which][scope] : per-queue sub toggle (2D)
-- PausedQueue[which][scope]  : per-queue pause state
-- A queue runs only if: Enabled[which] AND ScopeEnabled[which][scope]
-- which = 0 (top, slot13) or 1 (bottom, slot 14)
-- scope = 0 (instance) or 1 (out of instance)
TrinketMenuQueue = {
	Stats = {},
	Sort = {},
	Enabled = {},
	ScopeEnabled = {},
}
TrinketMenu.PausedQueue = {}
TrinketMenu.CurrentlySortingScope = 0

local function _tm_ensure_sort(which, scope)
	if type(which) ~= "number" or type(scope) ~= "number" then
		return {}
	end
	if type(TrinketMenuQueue) ~= "table" then
		TrinketMenuQueue = {}
	end
	if type(TrinketMenuQueue.Sort) ~= "table" then
		TrinketMenuQueue.Sort = {}
	end
	if type(TrinketMenuQueue.Sort[which]) ~= "table" then
		TrinketMenuQueue.Sort[which] = {}
	end
	TrinketMenuQueue.Sort[which][scope] = TrinketMenuQueue.Sort[which][scope] or {}
	return TrinketMenuQueue.Sort[which][scope]
end

function TrinketMenu.QueueInit()
	for which = 0, 1 do
		for scope = 0, 1 do
			_tm_ensure_sort(which, scope)
			if TrinketMenuQueue.Enabled[which] == nil then
				TrinketMenuQueue.Enabled[which] = 1
			end
			TrinketMenuQueue.ScopeEnabled = TrinketMenuQueue.ScopeEnabled or {}
			TrinketMenuQueue.ScopeEnabled[which] = type(TrinketMenuQueue.ScopeEnabled[which]) == "table"
				and TrinketMenuQueue.ScopeEnabled[which]
				or {}
			if TrinketMenuQueue.ScopeEnabled[which][scope] == nil then
				TrinketMenuQueue.ScopeEnabled[which][scope] = 1
			end
			TrinketMenu.PausedQueue[which] = TrinketMenu.PausedQueue[which] or {}
			-- new users: seed stop marker at position 1 so defaults queue nothing
			if not TrinketMenuQueue.Sort[which][scope][1] then
				table.insert(TrinketMenuQueue.Sort[which][scope], 0)
			end
		end
	end
	TrinketMenu_SubQueueFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	TrinketMenu_SortPriorityText:SetText("优先")
	TrinketMenu_SortPriorityText:SetTextColor(0.95, 0.95, 0.95)
	TrinketMenu_SortKeepEquippedText:SetText("暂停自动排队")
	TrinketMenu_SortKeepEquippedText:SetTextColor(0.95, 0.95, 0.95)
	TrinketMenu_SortListFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	TrinketMenu.ReflectQueueEnabled()
	TrinketMenu.UpdateCombatQueue()
	TrinketMenu.BagsNeedUpdating = {}
	TrinketMenu.CreateTimer("UpdateBaggedTrinkets", TrinketMenu.UpdateBaggedTrinkets, 0.2)
	TrinketMenu_MainFrame:RegisterEvent("BAG_UPDATE")
end

function TrinketMenu.ReflectQueueEnabled()
	getglobal("TrinketMenu_Trinket0Check"):SetChecked(TrinketMenuQueue.Enabled[0] == 1)
	getglobal("TrinketMenu_Trinket1Check"):SetChecked(TrinketMenuQueue.Enabled[1] == 1)
	local which = TrinketMenu.CurrentlySorting or 0
	local se = TrinketMenuQueue.ScopeEnabled and TrinketMenuQueue.ScopeEnabled[which] or {}
	local c0 = getglobal("TrinketMenu_ScopeTab0Check")
	local c1 = getglobal("TrinketMenu_ScopeTab1Check")
	if c0 then
		c0:SetChecked(se[0])
	end
	if c1 then
		c1:SetChecked(se[1])
	end
end

function TrinketMenu.OpenSort(which)
	TrinketMenu.CurrentlySorting = which
	TrinketMenu.PopulateSort(which, TrinketMenu.CurrentlySortingScope or 0)
	TrinketMenu.SortSelected = 0
	TrinketMenu_SortScrollScrollBar:SetValue(0)
	TrinketMenu.SortValidate()
	TrinketMenu.SortScrollFrameUpdate()
	TrinketMenu.ValidateChecks()
	TrinketMenu.ReflectQueueEnabled()
end

function TrinketMenu.ScopeTab_OnClick()
	local scope = this:GetID()
	TrinketMenu.CurrentlySortingScope = scope
	for i = 0, 1 do
		local tab = getglobal("TrinketMenu_ScopeTab" .. i)
		if tab then
			tab:UnlockHighlight()
		end
	end
	getglobal("TrinketMenu_ScopeTab" .. scope):LockHighlight()
	TrinketMenu.PopulateSort(TrinketMenu.CurrentlySorting or 0, scope)
	TrinketMenu.SortSelected = 0
	TrinketMenu_SortScrollScrollBar:SetValue(0)
	TrinketMenu.SortValidate()
	TrinketMenu.SortScrollFrameUpdate()
	TrinketMenu.ReflectQueueEnabled()
end

function TrinketMenu.GetID(bag, slot)
	local id
	if slot then
		_, _, id = string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+)")
	else
		_, _, id = string.find(GetInventoryItemLink("player", bag) or "", "item:(%d+)")
	end
	return id
end

function TrinketMenu.GetNameByID(id)
	if id == 0 then
		return StopQueueHereText1, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", 1
	else
		local name, _, quality, _, _, _, _, _, texture = GetItemInfo(id or "")
		return name, texture, quality
	end
end

-- adds id to which/scope sort if it's not already in the list
function TrinketMenu.AddToSort(which, scope, id)
	if not id then
		return
	end
	local name = TrinketMenu.GetNameByID(id)
	if name and not TrinketMenu.WatchItem[name] then
		TrinketMenu.AddWatchItem(name)
	end

	local list = _tm_ensure_sort(which, scope)
	local found
	for i = 1, table.getn(list) do
		found = found or list[i] == id
	end
	if not found then
		table.insert(list, id)
	end
end

-- populates sorts adding any new trinkets
function TrinketMenu.PopulateSort(which, scope)
	_tm_ensure_sort(which, scope)
	TrinketMenu.AddToSort(which, scope, TrinketMenu.GetID(which + 13))
	TrinketMenu.AddToSort(which, scope, TrinketMenu.GetID((1 - which) + 13))
	local equipLoc, id
	for i = 0, 4 do
		for j = 1, GetContainerNumSlots(i) do
			id = TrinketMenu.GetID(i, j)
			_, _, _, _, _, _, _, equipLoc = GetItemInfo(id or "")
			if equipLoc == "INVTYPE_TRINKET" then
				TrinketMenu.AddToSort(which, scope, id)
			end
		end
	end
	TrinketMenu.AddToSort(which, scope, 0) -- id 0 is Stop
end

function TrinketMenu.SortScrollFrameUpdate()
	local offset = FauxScrollFrame_GetOffset(TrinketMenu_SortScroll)
	local which = TrinketMenu.CurrentlySorting or 0
	local scope = TrinketMenu.CurrentlySortingScope or 0
	local list = _tm_ensure_sort(which, scope)
	FauxScrollFrame_Update(TrinketMenu_SortScroll, list and table.getn(list) or 0, 9, 20)

	if list then
		local r, g, b, found
		local texture, name, quality
		local item, itemName, itemIcon
		for i = 1, 9 do
			item = getglobal("TrinketMenu_Sort" .. i)
			itemName = getglobal("TrinketMenu_Sort" .. i .. "Name")
			itemIcon = getglobal("TrinketMenu_Sort" .. i .. "Icon")
			idx = offset + i
			if idx <= table.getn(list) then
				name, texture, quality = TrinketMenu.GetNameByID(list[idx])
				itemIcon:SetTexture(texture)
				itemName:SetText(name)
				r, g, b = GetItemQualityColor(quality)
				itemName:SetTextColor(r, g, b)
				itemIcon:SetVertexColor(1, 1, 1)
				item:Show()
				if idx == TrinketMenu.SortSelected then
					TrinketMenu.LockHighlight(item)
				else
					TrinketMenu.UnlockHighlight(item)
				end
			else
				item:Hide()
			end
		end
	end
end

function TrinketMenu.LockHighlight(frame)
	if type(frame) == "string" then
		frame = getglobal(frame)
	end
	if not frame then
		return
	end
	frame.lockedHighlight = 1
	getglobal(frame:GetName() .. "Highlight"):Show()
end

function TrinketMenu.UnlockHighlight(frame)
	if type(frame) == "string" then
		frame = getglobal(frame)
	end
	if not frame then
		return
	end
	frame.lockedHighlight = nil
	getglobal(frame:GetName() .. "Highlight"):Hide()
end

-- shows tooltip for items in the sort list
function TrinketMenu.SortTooltip()
	local idx = FauxScrollFrame_GetOffset(TrinketMenu_SortScroll) + this:GetID()
	local which = TrinketMenu.CurrentlySorting or 0
	local scope = TrinketMenu.CurrentlySortingScope or 0
	local list = _tm_ensure_sort(which, scope)
	local name, itemLink = GetItemInfo(list[idx] or "")
	if itemLink and TrinketMenuOptions.ShowTooltips == "ON" then
		TrinketMenu.AnchorTooltip()
		GameTooltip:SetHyperlink(itemLink)
		GameTooltip:Show()
	else
		TrinketMenu.OnTooltip(StopQueueHereText2, StopQueueHereTooltip)
	end
end

function TrinketMenu.SortOnClick()
	TrinketMenu_SortDelay:ClearFocus()
	local idx = FauxScrollFrame_GetOffset(TrinketMenu_SortScroll) + this:GetID()
	if TrinketMenu.SortSelected == idx then
		TrinketMenu.SortSelected = 0
	else
		TrinketMenu.SortSelected = idx
	end
	TrinketMenu.SortScrollFrameUpdate()
	TrinketMenu.SortValidate()
end

-- turns move buttons on/off, moves the list to keep selected in view and keeps the sorting slot button highlighted
function TrinketMenu.SortValidate()
	local selected = TrinketMenu.SortSelected
	local which = TrinketMenu.CurrentlySorting or 0
	local scope = TrinketMenu.CurrentlySortingScope or 0
	local list = _tm_ensure_sort(which, scope)
	TrinketMenu_MoveTop:Enable()
	TrinketMenu_MoveUp:Enable()
	TrinketMenu_MoveDown:Enable()
	TrinketMenu_MoveBottom:Enable()
	if selected == 0 or table.getn(list) < 2 then -- none selected, disable all
		TrinketMenu_MoveTop:Disable()
		TrinketMenu_MoveUp:Disable()
		TrinketMenu_MoveDown:Disable()
		TrinketMenu_MoveBottom:Disable()
	elseif selected == 1 then -- top selected, disable up
		TrinketMenu_MoveUp:Disable()
		TrinketMenu_MoveTop:Disable()
		TrinketMenu_MoveDown:Enable()
	elseif selected == table.getn(list) then -- bottom selected, disable down
		TrinketMenu_MoveDown:Disable()
		TrinketMenu_MoveBottom:Disable()
	end
	local idx = FauxScrollFrame_GetOffset(TrinketMenu_SortScroll)
	if selected > 0 and list[selected] and list[selected] ~= 0 then
		TrinketMenu_SortDelay:Show()
		TrinketMenu_SortPriority:Show()
		TrinketMenu_SortKeepEquipped:Show()
	else
		TrinketMenu_SortDelay:Hide()
		TrinketMenu_SortPriority:Hide()
		TrinketMenu_SortKeepEquipped:Hide()
	end
	local stats = TrinketMenuQueue.Stats[list[TrinketMenu.SortSelected]]
	TrinketMenu_SortDelay:SetText(stats and (stats.delay or "0") or "0")
	TrinketMenu_SortPriority:SetChecked(stats and stats.priority)
	TrinketMenu_SortKeepEquipped:SetChecked(stats and stats.keep)

	if not IsShiftKeyDown() and selected > 0 then -- keep selected visible on list, moving thumb as needed, unless shift is down
		local parent = TrinketMenu_SortScrollScrollBar
		local offset
		if selected <= idx then
			offset = (selected == 1) and 0 or (parent:GetValue() - (parent:GetHeight() / 2))
			parent:SetValue(offset)
			PlaySound("UChatScrollButton")
		elseif selected >= (idx + 10) then
			offset = (selected == table.getn(list)) and TrinketMenu_SortScroll:GetVerticalScrollRange()
				or (parent:GetValue() + (parent:GetHeight() / 2))
			parent:SetValue(offset)
			PlaySound("UChatScrollButton")
		end
	end
end

-- movement buttons
function TrinketMenu.SortMove()
	TrinketMenu_SortDelay:ClearFocus()
	local dir = ((this == TrinketMenu_MoveUp) and -1)
		or ((this == TrinketMenu_MoveTop) and "top")
		or ((this == TrinketMenu_MoveDown) and 1)
		or ((this == TrinketMenu_MoveBottom) and "bottom")
	if dir then
		local idx1 = TrinketMenu.SortSelected -- FauxScrollFrame_GetOffset(ItemRack_Config_SortScroll) +
		local which = TrinketMenu.CurrentlySorting or 0
		local scope = TrinketMenu.CurrentlySortingScope or 0
		local list = _tm_ensure_sort(which, scope)
		local idx2 = ((dir == "top") and 1) or ((dir == "bottom") and table.getn(list)) or idx1 + dir
		local temp = list[idx1]
		if tonumber(dir) then
			list[idx1] = list[idx2]
			list[idx2] = temp
		elseif dir == "top" then
			table.remove(list, idx1)
			table.insert(list, 1, temp)
		elseif dir == "bottom" then
			table.remove(list, idx1)
			table.insert(list, temp)
		end
		TrinketMenu.SortSelected = idx2
		TrinketMenu.SortValidate()
		TrinketMenu.SortScrollFrameUpdate()
	end
end

function TrinketMenu.SortDelay_OnTextChanged()
	local delay = tonumber(TrinketMenu_SortDelay:GetText()) or 0
	local which = TrinketMenu.CurrentlySorting or 0
	local scope = TrinketMenu.CurrentlySortingScope or 0
	local list = _tm_ensure_sort(which, scope)
	local id = list[TrinketMenu.SortSelected]
	TrinketMenuQueue.Stats[id] = TrinketMenuQueue.Stats[id] or {}
	TrinketMenuQueue.Stats[id].delay = delay ~= 0 and delay or nil
end

function TrinketMenu.SortPriority_OnClick()
	local check = this:GetChecked()
	local which = TrinketMenu.CurrentlySorting or 0
	local scope = TrinketMenu.CurrentlySortingScope or 0
	local list = _tm_ensure_sort(which, scope)
	local id = list[TrinketMenu.SortSelected]
	TrinketMenuQueue.Stats[id] = TrinketMenuQueue.Stats[id] or {}
	TrinketMenuQueue.Stats[id].priority = check
end

function TrinketMenu.SortKeepEquipped_OnClick()
	local check = this:GetChecked()
	local which = TrinketMenu.CurrentlySorting or 0
	local scope = TrinketMenu.CurrentlySortingScope or 0
	local list = _tm_ensure_sort(which, scope)
	local id = list[TrinketMenu.SortSelected]
	TrinketMenuQueue.Stats[id] = TrinketMenuQueue.Stats[id] or {}
	TrinketMenuQueue.Stats[id].keep = check
end

function TrinketMenu.TabCheck_OnClick()
	local which = 3 - this:GetID()
	TrinketMenuQueue.Enabled[which] = this:GetChecked() and 1 or false
	TrinketMenu.UpdateCombatQueue()
end

function TrinketMenu.ScopeEnable_OnClick()
	local scope = this:GetID()
	local which = TrinketMenu.CurrentlySorting or 0
	TrinketMenuQueue.ScopeEnabled = TrinketMenuQueue.ScopeEnabled or {}
	TrinketMenuQueue.ScopeEnabled[which] = TrinketMenuQueue.ScopeEnabled[which] or {}
	TrinketMenuQueue.ScopeEnabled[which][scope] = this:GetChecked() and 1 or false
	TrinketMenu.UpdateCombatQueue()
end

--[[ Auto queue processing ]]

function TrinketMenu.UpdateBaggedTrinkets()
	local id, name, equipLoc
	for i in TrinketMenu.BagsNeedUpdating do
		for j = 1, GetContainerNumSlots(i) do
			_, _, id = string.find(GetContainerItemLink(i, j) or "", "item:(%d+)")
			name, _, _, _, _, _, _, equipLoc = GetItemInfo(id or "")
			if equipLoc == "INVTYPE_TRINKET" then
				TrinketMenu.AddWatchItem(name, nil, i, j)
			end
		end
		TrinketMenu.BagsNeedUpdating[i] = nil
	end
end

function TrinketMenu.TrinketNearReady(bag, slot)
	local start, duration
	if slot then
		start, duration = GetContainerItemCooldown(bag, slot)
	else
		start, duration = GetInventoryItemCooldown("player", bag)
	end
	if start == 0 or duration - (GetTime() - start) <= 30 then
		return 1
	end
end

function TrinketMenu.CanCooldown(inv)
	local _, _, enable = GetInventoryItemCooldown("player", inv)
	return enable == 1
end

-- this function quickly checks if conditions are right for a possible ProcessAutoQueue
function TrinketMenu.PeriodicQueueCheck()
	if TrinketMenuOptions.DisableOnMount == "ON" and IsMounted() then
		return
	end
	local scope = IsInInstance() and 0 or 1
	for i = 0, 1 do
		if
			TrinketMenuQueue.Enabled[i] == 1
			and TrinketMenuQueue.ScopeEnabled
			and TrinketMenuQueue.ScopeEnabled[i]
			and TrinketMenuQueue.ScopeEnabled[i][scope] == 1
		then
			TrinketMenu.ProcessAutoQueue(i, scope)
		end
	end
end

-- which = 0 or 1, scope = 0 (instance) or 1 (out of instance)
function TrinketMenu.ProcessAutoQueue(which, scope)
	local start, duration, enable = GetInventoryItemCooldown("player", 13 + which)
	local _, _, id, name = string.find(GetInventoryItemLink("player", 13 + which) or "", "item:(%d+).+%[(.+)%]")
	local icon = getglobal("TrinketMenu_Trinket" .. which .. "Queue")

	if not id then
		return
	end -- leave if no trinket equipped
	if IsInventoryItemLocked(13 + which) then
		return
	end -- leave if slot being swapped
	if TrinketMenu.PausedQueue[which] and TrinketMenu.PausedQueue[which][scope] then
		icon:SetVertexColor(1, 0.5, 0.5) -- leave if SetQueue(which,scope,"PAUSE")
		return
	end
	if TrinketMenuQueue.Stats[id] then
		if TrinketMenuQueue.Stats[id].keep then
			icon:SetVertexColor(1, 0.5, 0.5)
			return -- leave if .keep flag set on this item
		end
		if TrinketMenuQueue.Stats[id].delay then
			local timeLeft = GetTime() - start
			-- leave if currently equipped trinket is on cooldown for less than its delay
			if start > 0 and (duration - timeLeft) > 30 and timeLeft < TrinketMenuQueue.Stats[id].delay then
				icon:SetDesaturated(1)
				return
			end
		end
	end

	icon:SetDesaturated(0) -- normal queue operation, reflect that in queue inset
	icon:SetVertexColor(1, 1, 1)

	--	local name = TrinketMenu.GetNameByID(id)
	local ready = TrinketMenu.TrinketNearReady(13 + which)
	if ready and TrinketMenu.CombatQueue[which] then
		TrinketMenu.CombatQueue[which] = nil
		TrinketMenu.UpdateCombatQueue()
	end
	local list = _tm_ensure_sort(which, scope)
	local rank
	for i = 1, table.getn(list) do
		if list[i] == 0 then
			rank = i
			break
		end
		if ready and list[i] == id then
			rank = i
			break
		end
	end
	if rank then
		local bag, slot
		for i = 1, rank do
			if
				not ready
				or enable == 0
				or (TrinketMenuQueue.Stats[list[i]] and TrinketMenuQueue.Stats[list[i]].priority)
			then
				name = GetItemInfo(list[i]) or ""
				if TrinketMenu.WatchItem[name] then
					bag, slot = TrinketMenu.WatchItem[name].bag, TrinketMenu.WatchItem[name].slot
					if bag then
						if string.find(GetContainerItemLink(bag, slot) or "", name, 1, 1) then
							if TrinketMenu.TrinketNearReady(bag, slot) then
								if TrinketMenu.CombatQueue[which] ~= name then
									TrinketMenu.EquipTrinketByName(name, 13 + which)
								end
								break
							end
						end
					end
				end
			end
		end
	end
end

--[[ TrinketMenu.SetQueue and TrinketMenu.GetQueue ]]

-- These functions are for macros and mods to configure sort queues.

-- TrinketMenu.SetQueue(which, scope, "ON" or "OFF" or "PAUSE" or "RESUME" or "SORT"[,"sort list"])
-- scope = 0 (instance) or 1 (out of instance)
-- some examples:
-- TrinketMenu.SetQueue(1, 0, "PAUSE") -- pause bottom trinket's instance queue
-- TrinketMenu.SetQueue(1, 0, "RESUME") -- resume it
-- TrinketMenu.SetQueue(1, 1, "SORT","Earthstrike","Insignia of the Alliance","Diamond Flask") -- set out-of-instance sort
-- TrinketMenu.SetQueue(0, 0, "SORT","Lifestone","Darkmoon Card: Heroism") -- set instance sort for top trinket
-- (a "stop the queue" is assumed at the end of the list)
function TrinketMenu.SetQueue(which, scope, ...)
	local errorstub = "|cFFBBBBBBTrinketMenu.SetQueue:|cFFFFFFFF "
	if not which or not tonumber(which) or which < 0 or which > 1 then
		DEFAULT_CHAT_FRAME:AddMessage(errorstub .. "First parameter must be 0 for top trinket or 1 for bottom.")
		return
	end
	if scope ~= 0 and scope ~= 1 then
		DEFAULT_CHAT_FRAME:AddMessage(errorstub .. "Second parameter must be 0 (instance) or 1 (out of instance).")
		return
	end
	if table.getn(arg) < 1 then
		DEFAULT_CHAT_FRAME:AddMessage(
			errorstub
				.. "Third parameter is either ON, OFF, PAUSE, RESUME or the beginning of a list of trinkets in a sort order."
		)
		return
	end
	if TrinketMenu_OptFrame:IsVisible() then
		TrinketMenu_OptFrame:Hide() -- close option frame if it's up. the mess otherwise would be scary
	end
	if TrinketMenuQueue.Enabled[which] == nil then
		TrinketMenuQueue.Enabled[which] = 1
	end
	TrinketMenuQueue.ScopeEnabled = TrinketMenuQueue.ScopeEnabled or {}
	TrinketMenuQueue.ScopeEnabled[which] = TrinketMenuQueue.ScopeEnabled[which] or {}
	TrinketMenu.PausedQueue[which] = TrinketMenu.PausedQueue[which] or {}
	local list = _tm_ensure_sort(which, scope)
	if arg[1] == "ON" then
		TrinketMenuQueue.ScopeEnabled[which][scope] = 1
		TrinketMenu.PausedQueue[which][scope] = nil
	elseif arg[1] == "OFF" then
		TrinketMenuQueue.ScopeEnabled[which][scope] = nil
		TrinketMenu.PausedQueue[which][scope] = nil
	elseif arg[1] == "PAUSE" then
		TrinketMenu.PausedQueue[which][scope] = 1
	elseif arg[1] == "RESUME" then
		TrinketMenu.PausedQueue[which][scope] = nil
	elseif arg[1] == "SORT" and table.getn(arg) > 1 then
		local sortidx, inv, bag, slot, id = 1
		table.setn(list, 0)
		for i = 2, table.getn(arg) do
			inv, bag, slot = TrinketMenu.FindItem(arg[i], 1) -- include inventory
			if inv then
				table.insert(list, TrinketMenu.GetID(inv))
			elseif bag then
				table.insert(list, TrinketMenu.GetID(bag, slot))
			else
				DEFAULT_CHAT_FRAME:AddMessage(errorstub .. 'Trinket "' .. arg[i] .. '" not found.')
			end
		end
		table.insert(list, 0)
	else
		DEFAULT_CHAT_FRAME:AddMessage(errorstub .. " Expected ON, OFF, PAUSE, RESUME or SORT+list")
	end

	TrinketMenu.ReflectQueueEnabled()
	TrinketMenu.UpdateCombatQueue()
end

-- returns 1 or nil if queue is enabled, and a table containing an ordered list of the trinkets
function TrinketMenu.GetQueue(which, scope)
	if not which or not tonumber(which) or which < 0 or which > 1 then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cFFBBBBBBTrinketMenu.GetQueue:|cFFFFFFFF Parameter must be 0 for top trinket or 1 for bottom."
		)
		return
	end
	if scope ~= 0 and scope ~= 1 then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cFFBBBBBBTrinketMenu.GetQueue:|cFFFFFFFF Second parameter must be 0 (instance) or 1 (out of instance)."
		)
		return
	end
	local list = _tm_ensure_sort(which, scope)
	local trinketList, name = {}
	for i = 1, table.getn(list) do
		name = TrinketMenu.GetNameByID(list[i])
		table.insert(trinketList, name)
	end
	local se = TrinketMenuQueue.ScopeEnabled and TrinketMenuQueue.ScopeEnabled[which]
	local en = se and se[scope]
	return en, trinketList
end

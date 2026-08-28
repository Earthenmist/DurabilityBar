local ADDON_NAME, addon = ...
addon = addon or {}
local DB

local function GetVersion()
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
  end
end

addon.version = GetVersion() or "Unknown"

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88DurabilityBar:|r " .. tostring(msg))
end

local function GetCoinTextureStringSafe(amount)
  if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
    return C_CurrencyInfo.GetCoinTextureString(amount)
  end
  return tostring(amount or 0)
end

local defaults = {
  point = "CENTER",
  relativeTo = "UIParent",
  relativePoint = "CENTER",
  x = 0,
  y = 0,
  width = 220,
  height = 28,
  scale = 1.0,
  locked = true,
  visible = true,
  showPercentText = true,
  showTooltip = true,
  hideAtFull = false,
  orientation = "HORIZONTAL",
  verticalText = true,
  autoSwapSize = true,
}

local function ApplyDefaults(t, d)
  if type(t) ~= "table" then t = {} end
  for k, v in pairs(d) do
    if t[k] == nil then
      t[k] = v
    elseif type(v) == "table" then
      t[k] = ApplyDefaults(t[k], v)
    end
  end
  return t
end

local frame = CreateFrame("Frame", "DurabilityBarFrame", UIParent, "TooltipBackdropTemplate")
frame:SetClampedToScreen(true)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:EnableMouse(true) -- Locked bars still need mouse input for their tooltip.
frame:RegisterForDrag("LeftButton")

local bar = CreateFrame("StatusBar", nil, frame)
bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
bar:SetMinMaxValues(0, 100)
bar:SetValue(100)

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Buttons\\WHITE8x8")
bg:SetAlpha(0.25)

local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
text:SetText("100%")

local function Layout()
  local pad = 6
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)

  bg:ClearAllPoints()
  bg:SetAllPoints(bar)

  text:ClearAllPoints()
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
end

frame:SetScript("OnDragStart", function(self)
  if DB.locked then return end
  self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, relativeTo, relativePoint, x, y = self:GetPoint()
  DB.point, DB.relativeTo, DB.relativePoint, DB.x, DB.y =
    point, (relativeTo and relativeTo:GetName()) or "UIParent", relativePoint, x, y
end)

local function UpdateLockState()
  frame:EnableMouse(true)
end

local function SetBarColor(pct)
  if pct >= 50 then
    bar:SetStatusBarColor(0.1, 0.8, 0.1)
  elseif pct >= 25 then
    bar:SetStatusBarColor(1.0, 0.6, 0.0)
  else
    bar:SetStatusBarColor(0.8, 0.1, 0.1)
  end
end

local function GetOverallDurability()
  local totalCur, totalMax = 0, 0
  for slot = 1, 17 do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      totalCur = totalCur + cur
      totalMax = totalMax + max
    end
  end
  if totalMax == 0 then return 100 end
  return math.floor((totalCur / totalMax) * 100 + 0.5)
end

local function FormatPercentText(pct)
  local s = pct .. "%"
  if (DB.orientation == "VERTICAL") and DB.verticalText then
    local stacked = s:gsub(".", "%0\n")
    return stacked:sub(1, -2) -- gsub adds a newline after the final character.
  end
  return s
end

local function Refresh()
  local pct = GetOverallDurability()
  bar:SetValue(pct)
  SetBarColor(pct)

  if DB.showPercentText then
    text:SetText(FormatPercentText(pct))
    text:Show()
  else
    text:Hide()
  end

  if not DB.visible or (DB.hideAtFull and pct == 100) then
    frame:Hide()
  else
    frame:Show()
  end
end

local optionsPanel
local syncingOptions = false

local function UpdateOrientation()
  local ori = (DB.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL"

  if bar.SetOrientation then
    bar:SetOrientation(ori)
    if bar.SetReverseFill then bar:SetReverseFill(false) end
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetValue(bar:GetValue())
  end

  if DB.autoSwapSize then
    if ori == "VERTICAL" and DB.height < DB.width then
      DB.width, DB.height = DB.height, DB.width
      frame:SetSize(DB.width, DB.height)
    elseif ori == "HORIZONTAL" and DB.width < DB.height then
      DB.width, DB.height = DB.height, DB.width
      frame:SetSize(DB.width, DB.height)
    end
  else
    if ori == "VERTICAL" and DB.height <= DB.width then
      DB.height = math.min(math.max(DB.width + 40, DB.height), 800)
      frame:SetHeight(DB.height)
    end
  end

  Layout()
  Refresh()

  if optionsPanel and optionsPanel._ApplySliderRanges then
    optionsPanel._ApplySliderRanges(ori)
  end
end

-- Tooltips stay disabled in combat to avoid protected-state interactions.
local DURABILITY_SLOTS = {
  { 1, "Head" },
  { 3, "Shoulder" },
  { 5, "Chest" },
  { 6, "Waist" },
  { 7, "Legs" },
  { 8, "Feet" },
  { 9, "Wrist" },
  { 10, "Hands" },
  { 16, "Main Hand" },
  { 17, "Off Hand" },
}

local function ShowTooltip()
  if not DB.showTooltip or InCombatLockdown() then return end
  GameTooltip:SetOwner(frame, "ANCHOR_TOP")
  GameTooltip:ClearLines()

  local overall = GetOverallDurability()
  GameTooltip:AddLine("Durability", 1, 1, 1)
  GameTooltip:AddLine(("Overall: |cffffffff%d%%|r"):format(overall), 0.9, 0.9, 0.9)

  for _, slotInfo in ipairs(DURABILITY_SLOTS) do
    local slot, label = slotInfo[1], slotInfo[2]
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      local pct = math.floor((cur / max) * 100 + 0.5)
      local r, g, b
      if pct >= 50 then
        r, g, b = 0.1, 0.8, 0.1
      elseif pct >= 25 then
        r, g, b = 1.0, 0.6, 0.0
      else
        r, g, b = 0.8, 0.1, 0.1
      end
      GameTooltip:AddDoubleLine(label, pct .. "%", 0.8, 0.8, 0.8, r, g, b)
    end
  end

  if MerchantFrame and MerchantFrame:IsShown() and CanMerchantRepair and CanMerchantRepair() then
    local cost = GetRepairAllCost()
    if cost and cost > 0 then
      GameTooltip:AddLine(("Repair cost: |cffffffff%s|r"):format(GetCoinTextureStringSafe(cost)), 0.9, 0.9, 0.9)
    end
  end

  GameTooltip:AddLine(" ", 0, 0, 0)
  GameTooltip:AddLine("Tip: Drag to move. Size via Options > AddOns > Durability Bar.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

frame:HookScript("OnEnter", function() ShowTooltip() end)
frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

local function CreateOptionsPanel()
  if optionsPanel then return end

  local panel = CreateFrame("Frame")
  panel.name = "Durability Bar"
  optionsPanel = panel

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Durability Bar")

  local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  versionText:SetText("v" .. (addon.version or "Unknown"))

  local function UpdateVersionText()
    if addon.version and addon.version ~= "Unknown" then
      versionText:SetText("v" .. addon.version)
    else
      C_Timer.After(1, UpdateVersionText)
    end
  end
  UpdateVersionText()

  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", 0, -6)
  sub:SetText("Adjust the appearance and behavior of the durability bar.")

  local lockCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  lockCB:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
  lockCB.text:SetText("Lock frame (disable drag)")
  lockCB:SetScript("OnClick", function(self)
    DB.locked = self:GetChecked()
    UpdateLockState()
  end)

  local textCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  textCB:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, -8)
  textCB.text:SetText("Show % text on the bar")
  textCB:SetScript("OnClick", function(self)
    DB.showPercentText = self:GetChecked()
    Refresh()
  end)

  local tipCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  tipCB:SetPoint("TOPLEFT", textCB, "BOTTOMLEFT", 0, -8)
  tipCB.text:SetText("Show tooltip (out of combat)")
  tipCB:SetScript("OnClick", function(self)
    DB.showTooltip = self:GetChecked()
    if not DB.showTooltip then GameTooltip:Hide() end
  end)

  local hideCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  hideCB:SetPoint("TOPLEFT", tipCB, "BOTTOMLEFT", 0, -8)
  hideCB.text:SetText("Hide when at 100% durability")
  hideCB:SetScript("OnClick", function(self)
    DB.hideAtFull = self:GetChecked()
    Refresh()
  end)

  local scaleSL = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  scaleSL:SetPoint("TOPLEFT", hideCB, "BOTTOMLEFT", 0, -24)
  scaleSL:SetWidth(260); scaleSL:SetMinMaxValues(0.5, 2.0)
  scaleSL:SetValueStep(0.05); scaleSL:SetObeyStepOnDrag(true)
  scaleSL:SetScript("OnValueChanged", function(self, val)
    if syncingOptions then return end
    DB.scale = tonumber(string.format("%.2f", val))
    frame:SetScale(DB.scale)
  end)
  scaleSL:EnableMouseWheel(true)
  scaleSL:SetScript("OnMouseWheel", function(_, delta)
    local step = IsShiftKeyDown() and 0.1 or 0.05
    local min, max = scaleSL:GetMinMaxValues()
    local v = math.min(max, math.max(min, (DB.scale or 1) + (delta > 0 and step or -step)))
    v = tonumber(string.format("%.2f", v))
    scaleSL:SetValue(v)
  end)
  scaleSL.Low:SetText("0.5"); scaleSL.High:SetText("2.0"); scaleSL.Text:SetText("Scale")

  local widthSL = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  widthSL:SetPoint("TOPLEFT", scaleSL, "BOTTOMLEFT", 24, -28)
  widthSL:SetWidth(212)
  widthSL:SetValueStep(1); widthSL:SetObeyStepOnDrag(true)

  local heightSL = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  heightSL:SetPoint("TOPLEFT", widthSL, "BOTTOMLEFT", 0, -28)
  heightSL:SetWidth(212)
  heightSL:SetValueStep(1); heightSL:SetObeyStepOnDrag(true)

  local function AddNudgers(slider)
    local dec = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    dec:SetSize(22, 22)
    dec:SetText("-")
    dec:SetPoint("RIGHT", slider, "LEFT", -6, 0)
    dec:SetScript("OnClick", function()
      local min, max = slider:GetMinMaxValues()
      local cur = slider:GetValue()
      local step = IsShiftKeyDown() and 5 or 1
      local newv = math.max(min, cur - step)
      slider:SetValue(newv)
    end)

    local inc = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    inc:SetSize(22, 22)
    inc:SetText("+")
    inc:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    inc:SetScript("OnClick", function()
      local min, max = slider:GetMinMaxValues()
      local cur = slider:GetValue()
      local step = IsShiftKeyDown() and 5 or 1
      local newv = math.min(max, cur + step)
      slider:SetValue(newv)
    end)

    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
      local min, max = slider:GetMinMaxValues()
      local cur = slider:GetValue()
      local step = IsShiftKeyDown() and 5 or 1
      local newv = cur + (delta > 0 and step or -step)
      newv = math.max(min, math.min(max, newv))
      slider:SetValue(newv)
    end)

    return dec, inc
  end

  widthSL:SetScript("OnValueChanged", function(self, val)
    if syncingOptions then return end
    DB.width = math.floor(val + 0.5)
    frame:SetWidth(DB.width)
    Layout()
    Refresh()
  end)
  heightSL:SetScript("OnValueChanged", function(self, val)
    if syncingOptions then return end
    DB.height = math.floor(val + 0.5)
    frame:SetHeight(DB.height)
    Layout()
    Refresh()
  end)

  AddNudgers(widthSL)
  AddNudgers(heightSL)

  local oriLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  oriLabel:SetPoint("TOPLEFT", heightSL, "BOTTOMLEFT", -24, -24)
  oriLabel:SetText("Orientation")

  local oriH = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
  oriH:SetPoint("TOPLEFT", oriLabel, "BOTTOMLEFT", 0, -6)
  oriH.text:SetText("Horizontal")

  local oriV = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
  oriV:SetPoint("LEFT", oriH, "RIGHT", 120, 0)
  oriV.text:SetText("Vertical")

  local function SetOri(choice)
    DB.orientation = choice
    UpdateOrientation()
    oriH:SetChecked(choice == "HORIZONTAL")
    oriV:SetChecked(choice == "VERTICAL")
  end

  oriH:SetScript("OnClick", function() SetOri("HORIZONTAL") end)
  oriV:SetScript("OnClick", function() SetOri("VERTICAL") end)

  local vtextCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  vtextCB:SetPoint("TOPLEFT", oriLabel, "BOTTOMLEFT", 0, -36)
  vtextCB.text:SetText("Stack % text vertically when bar is vertical")
  vtextCB:SetScript("OnClick", function(self)
    DB.verticalText = self:GetChecked()
    Refresh()
  end)

  local autoswapCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  autoswapCB:SetPoint("TOPLEFT", vtextCB, "BOTTOMLEFT", 0, -8)
  autoswapCB.text:SetText("Auto swap width/height when orientation changes")
  autoswapCB:SetScript("OnClick", function(self)
    DB.autoSwapSize = self:GetChecked()
  end)

  local swapBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  swapBtn:SetPoint("TOPLEFT", autoswapCB, "BOTTOMLEFT", 0, -12)
  swapBtn:SetSize(190, 22)
  swapBtn:SetText("Swap Orientation & Size")
  swapBtn:SetScript("OnClick", function()
    DB.width, DB.height = DB.height, DB.width
    local orientation = DB.orientation == "VERTICAL" and "HORIZONTAL" or "VERTICAL"
    SetOri(orientation)
  end)

  function panel._ApplySliderRanges(ori)
    if ori == "VERTICAL" then
      widthSL:SetMinMaxValues(16, 120)
      widthSL.Low:SetText("16"); widthSL.High:SetText("120")
      widthSL.Text:SetText("Width (Thickness)")

      heightSL:SetMinMaxValues(120, 800)
      heightSL.Low:SetText("120"); heightSL.High:SetText("800")
      heightSL.Text:SetText("Height (Length)")

      DB.width  = math.max(16, math.min(DB.width, 120))
      DB.height = math.max(120, math.min(DB.height, 800))
    else
      widthSL:SetMinMaxValues(160, 800)
      widthSL.Low:SetText("160"); widthSL.High:SetText("800")
      widthSL.Text:SetText("Width")

      heightSL:SetMinMaxValues(20, 120)
      heightSL.Low:SetText("20"); heightSL.High:SetText("120")
      heightSL.Text:SetText("Height")

      DB.width  = math.max(160, math.min(DB.width, 800))
      DB.height = math.max(20,  math.min(DB.height, 120))
    end

    frame:SetSize(DB.width, DB.height)
    widthSL:SetValue(DB.width)
    heightSL:SetValue(DB.height)
    Layout()
    Refresh()
  end

  local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetBtn:SetPoint("TOPLEFT", swapBtn, "BOTTOMLEFT", 0, -20)
  resetBtn:SetSize(120, 22); resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    wipe(DurabilityBarDB)
    DurabilityBarDB = ApplyDefaults(nil, defaults)
    DB = DurabilityBarDB
    frame:ClearAllPoints()
    frame:SetSize(DB.width, DB.height)
    frame:SetPoint(DB.point, UIParent, DB.relativePoint, DB.x, DB.y)
    frame:SetScale(DB.scale)
    UpdateLockState()
    UpdateOrientation()
    lockCB:SetChecked(DB.locked)
    textCB:SetChecked(DB.showPercentText)
    tipCB:SetChecked(DB.showTooltip)
    vtextCB:SetChecked(DB.verticalText)
    hideCB:SetChecked(DB.hideAtFull)
    autoswapCB:SetChecked(DB.autoSwapSize)
    oriH:SetChecked(true); oriV:SetChecked(false)
    scaleSL:SetValue(DB.scale)
    optionsPanel._ApplySliderRanges(DB.orientation)
    Print("Position & size reset.")
  end)

  local centerBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  centerBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
  centerBtn:SetSize(140, 22); centerBtn:SetText("Move to Center")
  centerBtn:SetScript("OnClick", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    DB.point, DB.relativeTo, DB.relativePoint, DB.x, DB.y = "CENTER", "UIParent", "CENTER", 0, 0
  end)

  local showBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  showBtn:SetPoint("LEFT", centerBtn, "RIGHT", 8, 0)
  showBtn:SetSize(100, 22); showBtn:SetText("Show/Hide")
  showBtn:SetScript("OnClick", function()
    DB.visible = not DB.visible
    Refresh()
  end)

  local function SyncOptionsControls()
    if not DB then return end

    syncingOptions = true

    lockCB:SetChecked(DB.locked and true or false)
    textCB:SetChecked(DB.showPercentText and true or false)
    tipCB:SetChecked(DB.showTooltip and true or false)
    hideCB:SetChecked(DB.hideAtFull and true or false)
    vtextCB:SetChecked(DB.verticalText and true or false)
    autoswapCB:SetChecked(DB.autoSwapSize and true or false)

    local ori = (DB.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL"
    oriH:SetChecked(ori == "HORIZONTAL")
    oriV:SetChecked(ori == "VERTICAL")

    scaleSL:SetValue(DB.scale or 1)

    syncingOptions = false

    optionsPanel._ApplySliderRanges(ori)
  end

  -- Retail's Settings canvas can paint the panel before every child has refreshed,
  -- so immediate and next-frame synchronization prevents stale first-open values.
  panel:SetScript("OnShow", function()
    SyncOptionsControls()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, SyncOptionsControls)
    end
  end)

  panel._SyncOptionsControls = SyncOptionsControls

  -- Classic clients use the legacy category API when Retail Settings is absent.
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = "DurabilityBar_Options"
    Settings.RegisterAddOnCategory(category)
    panel._categoryID = category.ID
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  else
    panel:Hide()
  end

  SyncOptionsControls()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, SyncOptionsControls)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_LOGOUT")

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end

    DurabilityBarDB = ApplyDefaults(DurabilityBarDB, defaults)
    DB = DurabilityBarDB

    frame:SetSize(DB.width, DB.height)
    frame:ClearAllPoints()
    local rel = _G[DB.relativeTo] or UIParent
    frame:SetPoint(DB.point, rel, DB.relativePoint, DB.x, DB.y)
    frame:SetScale(DB.scale or 1)

    frame:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    UpdateLockState()
    UpdateOrientation()
    CreateOptionsPanel()

    SLASH_DURABILITYBAR1 = "/durabar"
    SlashCmdList["DURABILITYBAR"] = function(msg)
      msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

      if msg == "options" or msg == "opt" or msg == "" then
        if Settings and Settings.OpenToCategory then
          local id = optionsPanel and optionsPanel._categoryID or "Durability Bar"
          Settings.OpenToCategory(id)
        elseif InterfaceOptionsFrame_OpenToCategory then
          InterfaceOptionsFrame_OpenToCategory("Durability Bar")
          InterfaceOptionsFrame_OpenToCategory("Durability Bar")
        end

      elseif msg == "lock" then
        DB.locked = true; UpdateLockState(); Print("Locked.")

      elseif msg == "unlock" then
        DB.locked = false; UpdateLockState(); Print("Unlocked.")

      elseif msg == "reset" then
        wipe(DurabilityBarDB)
        DurabilityBarDB = ApplyDefaults(nil, defaults); DB = DurabilityBarDB
        frame:ClearAllPoints()
        frame:SetSize(DB.width, DB.height)
        frame:SetPoint(DB.point, UIParent, DB.relativePoint, DB.x, DB.y)
        frame:SetScale(DB.scale)
        UpdateLockState()
        UpdateOrientation()
        Print("Position & size reset.")

      elseif msg == "text" then
        DB.showPercentText = not DB.showPercentText; Refresh()
        Print("Percent text " .. (DB.showPercentText and "shown" or "hidden") .. ".")

      elseif msg == "vertical" or msg == "v" then
        DB.orientation = "VERTICAL"; UpdateOrientation(); Print("Orientation: vertical.")

      elseif msg == "horizontal" or msg == "h" then
        DB.orientation = "HORIZONTAL"; UpdateOrientation(); Print("Orientation: horizontal.")

      elseif msg == "swap" then
        DB.width, DB.height = DB.height, DB.width
        DB.orientation = DB.orientation == "VERTICAL" and "HORIZONTAL" or "VERTICAL"
        UpdateOrientation()
        if optionsPanel and optionsPanel._SyncOptionsControls then
          optionsPanel._SyncOptionsControls()
        end
        Print("Swapped orientation, width, and height.")

      else
        Print("Use /durabar or /durabar options to open settings.")
      end
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    GameTooltip:Hide()

  elseif event == "PLAYER_LOGOUT" then
    DurabilityBarDB = DB

  else
    Refresh()
  end
end)

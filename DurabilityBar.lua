local ADDON_NAME = ...
local DB

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88DurabilityBar:|r " .. tostring(msg))
end

-- Defaults
local defaults = {
  point = "CENTER",
  relativeTo = "UIParent",
  relativePoint = "CENTER",
  x = 0,
  y = 0,
  width = 220,
  height = 28,
  scale = 1.0,
  locked = false,
  showPercentText = true,
  showTooltip = true,   -- tooltip toggle
  hideAtFull = false,   -- NEW: hide bar when at 100%
}

-- Utility: apply defaults
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

-- Holder with Blizzard rounded border (TooltipBackdropTemplate)
local frame = CreateFrame("Frame", "DurabilityBarFrame", UIParent, "TooltipBackdropTemplate")
frame:SetClampedToScreen(true)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:EnableMouse(true) -- keep enabled even when locked so tooltip works
frame:RegisterForDrag("LeftButton")

-- Status bar
local bar = CreateFrame("StatusBar", nil, frame)
bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
bar:SetMinMaxValues(0, 100)
bar:SetValue(100)

-- Background
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Buttons\\WHITE8x8")
bg:SetAlpha(0.25)

-- % text
local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
text:SetText("100%")

-- Resize grip
local resize = CreateFrame("Button", nil, frame)
resize:SetSize(16, 16)
resize:SetPoint("BOTTOMRIGHT", -6, 6)
resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

frame:SetResizable(true)
if frame.SetResizeBounds then
  frame:SetResizeBounds(160, 24, 600, 60) -- Retail DF+
else
  frame:SetMinResize(160, 24)             -- pre-DF fallback
  frame:SetMaxResize(600, 60)
end

-- Layout
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

-- Dragging
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

-- Resizing
resize:SetScript("OnMouseDown", function()
  if DB.locked then return end
  frame:StartSizing("BOTTOMRIGHT")
end)
resize:SetScript("OnMouseUp", function()
  frame:StopMovingOrSizing()
  DB.width = math.floor(frame:GetWidth() + 0.5)
  DB.height = math.floor(frame:GetHeight() + 0.5)
  Layout()
end)

-- Lock visuals (keep mouse enabled so tooltip still fires)
local function UpdateLockState()
  -- frame:EnableMouse(false) -- REMOVED to allow tooltip when locked
  frame:EnableMouse(true)
  if DB.locked then
    resize:Hide()
  else
    resize:Show()
  end
end

-- Color thresholds
local function SetBarColor(pct)
  if pct >= 50 then
    bar:SetStatusBarColor(0.1, 0.8, 0.1)    -- green
  elseif pct >= 25 then
    bar:SetStatusBarColor(1.0, 0.6, 0.0)    -- amber
  else
    bar:SetStatusBarColor(0.8, 0.1, 0.1)    -- red
  end
end

-- Overall durability %
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

-- Refresh (now also applies hide-at-full)
local function Refresh()
  local pct = GetOverallDurability()
  bar:SetValue(pct)
  SetBarColor(pct)

  if DB.showPercentText then
    text:SetText(pct .. "%")
    text:Show()
  else
    text:Hide()
  end

  if DB.hideAtFull and pct == 100 then
    frame:Hide()
  else
    frame:Show()
  end
end

-- ===== Tooltip (only out of combat) =====
local SLOT_LABELS = {
  [1] = "Head",      [2] = "Neck",      [3] = "Shoulder",
  [5] = "Chest",     [6] = "Waist",     [7] = "Legs",
  [8] = "Feet",      [9] = "Wrist",     [10] = "Hands",
  [16] = "Main Hand",[17] = "Off Hand",
}

local function ShowTooltip()
  if not DB.showTooltip or InCombatLockdown() then return end
  GameTooltip:SetOwner(frame, "ANCHOR_TOP")
  GameTooltip:ClearLines()

  local overall = GetOverallDurability()
  GameTooltip:AddLine("Durability", 1, 1, 1)
  GameTooltip:AddLine(("Overall: |cffffffff%d%%|r"):format(overall), 0.9, 0.9, 0.9)

  -- Per-slot quick view (only slots with durability)
  for slot, label in pairs(SLOT_LABELS) do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      local pct = math.floor((cur / max) * 100 + 0.5)
      local r, g, b
      if pct >= 50 then
        r, g, b = 0.1, 0.8, 0.1      -- green
      elseif pct >= 25 then
        r, g, b = 1.0, 0.6, 0.0      -- amber
      else
        r, g, b = 0.8, 0.1, 0.1      -- red
      end
      GameTooltip:AddDoubleLine(label, pct .. "%", 0.8, 0.8, 0.8, r, g, b)
    end
  end

  -- Repair cost if at a repair-capable merchant
  if MerchantFrame and MerchantFrame:IsShown() and CanMerchantRepair and CanMerchantRepair() then
    local cost = GetRepairAllCost()
    if cost and cost > 0 then
      GameTooltip:AddLine(("Repair cost: |cffffffff%s|r"):format(GetCoinTextureString(cost)), 0.9, 0.9, 0.9)
    end
  end

  GameTooltip:AddLine(" ", 0, 0, 0)
  GameTooltip:AddLine("Tip: Drag to move; resize from corner when unlocked.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

frame:HookScript("OnEnter", function() ShowTooltip() end)
frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
-- ===== end Tooltip =====

-- ===== Options Panel =====
local optionsPanel
local function CreateOptionsPanel()
  if optionsPanel then return end

  local panel = CreateFrame("Frame")
  panel.name = "Durability Bar"
  optionsPanel = panel

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Durability Bar")

  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Adjust the appearance and behavior of the durability bar.")

  -- Lock checkbox
  local lockCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  lockCB:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
  lockCB.text:SetText("Lock frame (disable drag/resize)")
  lockCB:SetScript("OnClick", function(self)
    DB.locked = self:GetChecked()
    UpdateLockState()
  end)

  -- Percent text checkbox
  local textCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  textCB:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, -8)
  textCB.text:SetText("Show % text on the bar")
  textCB:SetScript("OnClick", function(self)
    DB.showPercentText = self:GetChecked()
    Refresh()
  end)

  -- Tooltip checkbox
  local tipCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  tipCB:SetPoint("TOPLEFT", textCB, "BOTTOMLEFT", 0, -8)
  tipCB.text:SetText("Show tooltip (out of combat)")
  tipCB:SetScript("OnClick", function(self)
    DB.showTooltip = self:GetChecked()
    if not DB.showTooltip then GameTooltip:Hide() end
  end)

  -- Hide-at-full checkbox (NEW)
  local hideCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  hideCB:SetPoint("TOPLEFT", tipCB, "BOTTOMLEFT", 0, -8)
  hideCB.text:SetText("Hide when at 100% durability")
  hideCB:SetScript("OnClick", function(self)
    DB.hideAtFull = self:GetChecked()
    Refresh()
  end)

  -- Scale slider
  local scaleSL = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  scaleSL:SetPoint("TOPLEFT", hideCB, "BOTTOMLEFT", 0, -24)
  scaleSL:SetWidth(260); scaleSL:SetMinMaxValues(0.5, 2.0)
  scaleSL:SetValueStep(0.05); scaleSL:SetObeyStepOnDrag(true)
  scaleSL:SetScript("OnValueChanged", function(self, val)
    DB.scale = tonumber(string.format("%.2f", val))
    frame:SetScale(DB.scale)
  end)
  scaleSL.Low:SetText("0.5"); scaleSL.High:SetText("2.0"); scaleSL.Text:SetText("Scale")

  -- Width slider
  local widthSL = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  widthSL:SetPoint("TOPLEFT", scaleSL, "BOTTOMLEFT", 0, -24)
  widthSL:SetWidth(260); widthSL:SetMinMaxValues(160, 600)
  widthSL:SetValueStep(1); widthSL:SetObeyStepOnDrag(true)
  widthSL.Low:SetText("160"); widthSL.High:SetText("600"); widthSL.Text:SetText("Width")
  widthSL:SetScript("OnValueChanged", function(self, val)
    DB.width = math.floor(val + 0.5)
    frame:SetWidth(DB.width)
    Layout()
  end)

  -- Height slider
  local heightSL = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  heightSL:SetPoint("TOPLEFT", widthSL, "BOTTOMLEFT", 0, -24)
  heightSL:SetWidth(260); heightSL:SetMinMaxValues(24, 60)
  heightSL:SetValueStep(1); heightSL:SetObeyStepOnDrag(true)
  heightSL.Low:SetText("24"); heightSL.High:SetText("60"); heightSL.Text:SetText("Height")
  heightSL:SetScript("OnValueChanged", function(self, val)
    DB.height = math.floor(val + 0.5)
    frame:SetHeight(DB.height)
    Layout()
  end)

  -- Buttons
  local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetBtn:SetPoint("TOPLEFT", heightSL, "BOTTOMLEFT", 0, -20)
  resetBtn:SetSize(120, 22); resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    wipe(DurabilityBarDB)
    DurabilityBarDB = ApplyDefaults(nil, defaults)
    DB = DurabilityBarDB
    frame:ClearAllPoints()
    frame:SetSize(DB.width, DB.height)
    frame:SetPoint(DB.point, UIParent, DB.relativePoint, DB.x, DB.y)
    frame:SetScale(DB.scale)
    Layout(); UpdateLockState(); Refresh()
    lockCB:SetChecked(DB.locked)
    textCB:SetChecked(DB.showPercentText)
    tipCB:SetChecked(DB.showTooltip)
    hideCB:SetChecked(DB.hideAtFull)
    scaleSL:SetValue(DB.scale); widthSL:SetValue(DB.width); heightSL:SetValue(DB.height)
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
    if frame:IsShown() then frame:Hide() else frame:Show() end
  end)

  -- Sync widgets from DB when opened
  panel:SetScript("OnShow", function()
    lockCB:SetChecked(DB.locked)
    textCB:SetChecked(DB.showPercentText)
    tipCB:SetChecked(DB.showTooltip)
    hideCB:SetChecked(DB.hideAtFull)
    scaleSL:SetValue(DB.scale or 1)
    widthSL:SetValue(DB.width or 220)
    heightSL:SetValue(DB.height or 28)
  end)

  -- Register with Retail Settings UI (Dragonflight+)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = "DurabilityBar_Options"
    Settings.RegisterAddOnCategory(category)
    panel._categoryID = category.ID
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel) -- fallback
  else
    panel:Hide()
  end
end
-- ===== end Options Panel =====

-- Events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED") -- hide tooltip on combat start

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    DurabilityBarDB = ApplyDefaults(DurabilityBarDB, defaults)
    DB = DurabilityBarDB

    -- Size, pos, scale and visuals
    frame:SetSize(DB.width, DB.height)
    frame:ClearAllPoints()
    local rel = _G[DB.relativeTo] or UIParent
    frame:SetPoint(DB.point, rel, DB.relativePoint, DB.x, DB.y)
    frame:SetScale(DB.scale or 1)

    frame:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    Layout()
    UpdateLockState()
    Refresh()
    CreateOptionsPanel()

    -- Slash command
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
        Layout(); UpdateLockState(); Refresh()
        Print("Position & size reset.")

      elseif msg == "text" then
        DB.showPercentText = not DB.showPercentText; Refresh()
        Print("Percent text " .. (DB.showPercentText and "shown" or "hidden") .. ".")

      else
        Print("Use /durabar or /durabar options to open settings.")
      end
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    GameTooltip:Hide()

  else
    -- Any other registered event just refreshes the value/color & hide logic
    Refresh()
  end
end)

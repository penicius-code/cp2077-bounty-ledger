-- Cyberslop CET Style 1.0.0 (2026-11-22): this mod's windows use the gold palette (cyberslop_palette.lua, colours only).
do
  local ok, palette = pcall(require, "cyberslop_palette")
  if ok and type(palette) == "table" and type(registerForEvent) == "function" then
    local reg = registerForEvent
    registerForEvent = function(ev, fn)
      if ev == "onDraw" and type(fn) == "function" then fn = palette.wrap("gold", fn) end
      return reg(ev, fn)
    end
  end
end
-- Cyberslop NCPD Uplink 1.0.0 (2026-11-06)
-- CET window for Cyberslop Bounty Ledger 1.1.4+: the NCPD claim file Regina Jones keeps for V.
--   Transfer: open batch, countdown to the payout (game clock, plus a real-time estimate), progress bar.
--   Claims on file: who, faction, stars, alive / deceased, pay, where the body is (a claimed-alive
--   target that died drops to the dead rate at payout: flagged in red).
--   Warrants this session (Deep Scan civilians): offence, class, fee, open / served / killed, distance.
--   Journal: the last 40 Ledger events with game time (kept in the save).
--   Ledger: lifetime paid, batches, last payout; the current rates from Mod Settings.
-- Shows with the CET overlay. Hotkeys (CET Bindings, unbound by default):
--   "Pin NCPD uplink"  keeps a compact read-only panel on screen with the overlay closed.
--   "Ask Regina"       one HUD line from Regina with the state of your file.
-- Read-only: calls only the Ledger's accessors.

local Up = {
  version = "1.0.0",
  overlay = false,
  pinned = false,
  data = nil,
  nextPoll = 0,
  rateT0 = nil, rateG0 = nil, scale = nil,
}

local function sys(name)
  local ok, s = pcall(function() return Game.GetScriptableSystemsContainer():Get(name) end)
  if ok and s then return s end
  return nil
end

local function num(v)
  local s = tostring(math.floor((v or 0) + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

local function gameNow()
  local ok, t = pcall(function() return Game.GetTimeSystem():GetGameTimeStamp() end)
  return (ok and t) or 0
end

local function clockOf(t)
  if not t or t <= 0 then return "--:--" end
  local day = math.floor(t / 86400)
  local s = t - day * 86400
  return string.format("day %d %02d:%02d", day, math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local function hhmm(t)
  if not t or t <= 0 then return "--:--" end
  local s = t % 86400
  return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local function stars(n)
  n = n or 0
  if n <= 0 then return "-" end
  return string.rep("*", n)
end

local unpackArgs = table.unpack or unpack

local function call(obj, fn, ...)
  local args = { n = select("#", ...), ... }
  local ok, v = pcall(function() return obj[fn](obj, unpackArgs(args, 1, args.n)) end)
  if ok then return v end
  return nil
end

-- Game seconds per real second, measured over ~10 s windows (pauses and menus excluded).
local function measureScale(now)
  local t = os.clock()
  if not Up.rateT0 then Up.rateT0, Up.rateG0 = t, now return end
  local dt = t - Up.rateT0
  if dt < 10 then return end
  local dg = now - Up.rateG0
  if dg > 0 and dg / dt < 3600 then Up.scale = dg / dt end
  Up.rateT0, Up.rateG0 = t, now
end

local function poll()
  local ledger = sys("CyberslopBountyLedger.BountyLedger")
  local player = Game.GetPlayer()
  if not ledger or not player then Up.data = nil return end
  local now = gameNow()
  measureScale(now)
  local d = { now = now, claims = {}, warrants = {}, journal = {} }

  pcall(function()
    d.link = Game.GetStatsSystem():GetStatValue(player:GetEntityID(), gamedataStatType.HasLinkToBountySystem) > 0
  end)

  d.total = ledger.pendingTotal or 0
  d.count = ledger.pendingClaims or 0
  d.dead = ledger.pendingDeceased or 0
  d.dueAt = ledger.dueAt or 0
  d.openedAt = call(ledger, "BatchOpenedAt") or 0
  d.lifePaid = ledger.lifetimePaid or 0
  d.lifeClaims = ledger.lifetimeClaims or 0
  d.lifeBatches = ledger.lifetimeBatches or 0
  d.lastAt = ledger.lastPayoutAt or 0
  d.lastAmount = ledger.lastPayoutAmount or 0

  local n = call(ledger, "ClaimCount") or 0
  for i = 0, n - 1 do
    local c = {
      name = call(ledger, "ClaimName", i) or "unknown",
      faction = call(ledger, "ClaimFaction", i) or "",
      stars = call(ledger, "ClaimStars", i) or 0,
      warrant = call(ledger, "ClaimIsWarrant", i) or false,
      alive = call(ledger, "ClaimAlive", i) or false,
      pay = call(ledger, "ClaimPay", i) or 0,
      dist = call(ledger, "ClaimDistance", i) or -1,
      bodyDead = call(ledger, "ClaimBodyDead", i) or false,
    }
    table.insert(d.claims, c)
  end

  local w = sys("CyberslopBountyLedger.CSBLWarrants")
  if w then
    local fc = call(w, "FlaggedCount") or 0
    for i = 0, fc - 1 do
      table.insert(d.warrants, {
        label = call(w, "FlaggedLabel", i) or "?",
        stars = call(w, "FlaggedStars", i) or 0,
        pay = call(w, "FlaggedPay", i) or 0,
        state = call(w, "FlaggedState", i) or 0,
        dist = call(w, "FlaggedDistance", i) or -1,
      })
    end
  end

  local jn = call(ledger, "JournalCount") or 0
  for i = jn - 1, 0, -1 do
    table.insert(d.journal, {
      t = call(ledger, "JournalTime", i) or 0,
      kind = call(ledger, "JournalKind", i) or 0,
      text = call(ledger, "JournalText", i) or "",
    })
  end

  local s = sys("CyberslopBountyLedger.BountyLedgerSettings")
  if s then
    pcall(function()
      d.rates = { alive = s.alivePercent, dead = s.deadPercent, mins = s.processingMinutes,
                  p = { s.price1, s.price2, s.price3, s.price4, s.price5 }, enabled = s.enabled }
    end)
  end
  Up.data = d
end

local function remaining(d)
  if d.count <= 0 or d.dueAt <= 0 then return nil end
  return math.max(0, d.dueAt - d.now)
end

local function realHint(sec)
  if not Up.scale or Up.scale <= 0 then return "" end
  local r = sec / Up.scale
  if r < 90 then return string.format(" (~%d s real)", math.floor(r + 0.5)) end
  return string.format(" (~%.1f min real)", r / 60)
end

-- HUD line from Regina.
local function askRegina()
  pcall(poll)
  local d = Up.data
  local text
  if not d then
    text = "Regina Jones: Can't reach your file right now, choom."
  elseif d.link == false then
    text = "Regina Jones: Your optics have no NCPD link. No link, no claims."
  elseif d.count <= 0 then
    if d.lastAmount > 0 then
      text = string.format("Regina Jones: Nothing on file. Last transfer was %s eddies, %s. Bring me someone.", num(d.lastAmount), clockOf(d.lastAt))
    else
      text = "Regina Jones: Nothing on file. Scan them first, bring them in breathing."
    end
  else
    local left = remaining(d) or 0
    text = string.format("Regina Jones: %d %s on file, %s eddies. NCPD clears it at %s, about %d min.",
      d.count, d.count == 1 and "claim" or "claims", num(d.total), hhmm(d.dueAt), math.max(1, math.ceil(left / 60)))
    for _, c in ipairs(d.claims) do
      if c.alive and c.bodyDead then
        text = text .. " One of yours died in custody, that pays the dead rate."
        break
      end
    end
  end
  pcall(function()
    local msg = SimpleScreenMessage.new()
    msg.message = text
    msg.duration = 6.0
    msg.isShown = true
    msg.isInstant = true
    msg.type = SimpleMessageType.Police
    local defs = Game.GetAllBlackboardDefs()
    Game.GetBlackboardSystem():Get(defs.UI_Notifications):SetVariant(defs.UI_Notifications.WarningMessage, ToVariant(msg), true)
  end)
end

registerForEvent("onInit", function()
  print("[CyberslopBountyUplink] " .. Up.version .. " loaded")
end)
registerForEvent("onOverlayOpen", function() Up.overlay = true end)
registerForEvent("onOverlayClose", function() Up.overlay = false end)
registerHotkey("CyberslopBountyUplinkPin", "Pin NCPD uplink", function() Up.pinned = not Up.pinned end)
registerHotkey("CyberslopBountyUplinkAsk", "Ask Regina (HUD line)", askRegina)

local CYAN  = { 0.35, 0.90, 0.95, 1.0 }
local RED   = { 1.00, 0.33, 0.30, 1.0 }
local AMBER = { 1.00, 0.75, 0.30, 1.0 }
local GREEN = { 0.50, 0.95, 0.60, 1.0 }
local GREY  = { 0.62, 0.62, 0.62, 1.0 }
local GOLD  = { 1.00, 0.86, 0.40, 1.0 }

local function col(c, text) ImGui.TextColored(c[1], c[2], c[3], c[4], text) end

local function journalColor(kind)
  if kind == 6 then return GOLD end
  if kind == 1 or kind == 3 then return GREEN end
  if kind == 4 or kind == 5 or kind == 10 then return RED end
  if kind == 7 or kind == 8 then return AMBER end
  if kind == 9 then return CYAN end
  return GREY
end

local function where(dist)
  if not dist or dist < 0 then return "out of range" end
  return string.format("%d m", math.floor(dist + 0.5))
end

local function drawTransfer(d, compact)
  local left = remaining(d)
  if left then
    col(GOLD, string.format("TRANSFER PENDING  %s eddies", num(d.total)))
    local span = d.dueAt - (d.openedAt > 0 and d.openedAt or d.dueAt)
    local frac = (span > 0) and math.min(1, math.max(0, 1 - left / span)) or 0
    ImGui.ProgressBar(frac, compact and 220 or 360, 0, string.format("clears %s, in %.1f game min%s", hhmm(d.dueAt), left / 60, realHint(left)))
    local tail = string.format("%d %s", d.count, d.count == 1 and "claim" or "claims")
    if d.dead > 0 then tail = tail .. string.format(", %d deceased", d.dead) end
    col(GREY, "  " .. tail)
  else
    col(GREY, "No open file. Regina is waiting for your next collar.")
  end
end

local function drawFull(d)
  col(CYAN, "NCPD BOUNTY UPLINK  ·  claims brokered by Regina Jones")
  ImGui.SameLine()
  col(GREY, "   " .. clockOf(d.now))
  if d.link == false then
    col(RED, "Optics: no NCPD link. Kills and takedowns can't be claimed.")
  elseif d.rates and d.rates.enabled == false then
    col(AMBER, "Bounty Ledger is switched off in Mod Settings (vanilla bounties).")
  else
    col(GREEN, "Optics: NCPD link active. Scan first, then take them down.")
  end

  ImGui.Separator()
  drawTransfer(d, false)

  ImGui.Separator()
  col(CYAN, "CLAIMS ON FILE")
  if #d.claims == 0 then
    col(GREY, "  none")
  else
    for _, c in ipairs(d.claims) do
      local who = c.warrant and ("Warrant: " .. c.name) or c.name
      if not c.warrant and c.faction ~= "" and not string.find(c.name, c.faction, 1, true) then
        who = who .. " (" .. c.faction .. ")"
      end
      local status, sc
      if c.alive and c.bodyDead then
        status, sc = "DIED IN CUSTODY, dead rate at payout", RED
      elseif c.alive then
        status, sc = "alive", GREEN
      else
        status, sc = "deceased", AMBER
      end
      col(sc, string.format("  %-5s %-34s %6s eb  %s  [%s]", stars(c.stars), who, num(c.pay), status, where(c.dist)))
    end
  end

  if #d.warrants > 0 then
    ImGui.Separator()
    col(CYAN, "WARRANTS THIS SESSION")
    for _, w in ipairs(d.warrants) do
      local st, sc = "OPEN, bring in alive", CYAN
      if w.state == 1 then st, sc = "served", GREEN elseif w.state == 2 then st, sc = "killed, no fee", RED
      elseif w.state == 3 then st, sc = "died (not by V)", GREY end   -- Bounty Ledger 1.1.7
      col(sc, string.format("  %-5s %-30s fee %5s eb  %s  [%s]", stars(w.stars), w.label, num(w.pay), st, where(w.dist)))
    end
  end

  ImGui.Separator()
  col(CYAN, "JOURNAL")
  if #d.journal == 0 then
    col(GREY, "  nothing yet")
  else
    if ImGui.BeginChild("##uplinkJournal", 640, 170, true) then
      for _, j in ipairs(d.journal) do
        col(GREY, clockOf(j.t))
        ImGui.SameLine()
        col(journalColor(j.kind), j.text)
      end
    end
    ImGui.EndChild()
  end

  ImGui.Separator()
  col(GREY, string.format("Lifetime: %s eddies in %d transfers, %d claims.   Last transfer: %s",
    num(d.lifePaid), d.lifeBatches, d.lifeClaims, d.lastAmount > 0 and (num(d.lastAmount) .. " eb, " .. clockOf(d.lastAt)) or "none"))
  if d.rates then
    local p = d.rates.p or {}
    col(GREY, string.format("Rates: alive %d %%, dead %d %%, processing %d game min.   Stars 1-5: %s / %s / %s / %s / %s eb",
      d.rates.alive or 0, d.rates.dead or 0, d.rates.mins or 0,
      num(p[1]), num(p[2]), num(p[3]), num(p[4]), num(p[5])))
  end
end

registerForEvent("onDraw", function()
  if not Up.overlay and not Up.pinned then return end
  local t = os.clock()
  if t >= Up.nextPoll then
    Up.nextPoll = t + 1.0
    pcall(poll)
  end
  local d = Up.data

  if Up.overlay then
    if ImGui.Begin("Cyberslop NCPD Uplink", ImGuiWindowFlags.AlwaysAutoResize) then
      if not d then
        ImGui.Text("No uplink: no save loaded, or Cyberslop Bounty Ledger 1.1.4+ is missing.")
      else
        local ok, err = pcall(drawFull, d)
        if not ok then ImGui.Text("draw error: " .. tostring(err)) end
      end
    end
    ImGui.End()
    return
  end

  -- Pinned, overlay closed: compact read-only panel.
  if not d then return end
  local flags = ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoInputs + ImGuiWindowFlags.AlwaysAutoResize
    + ImGuiWindowFlags.NoFocusOnAppearing + ImGuiWindowFlags.NoNav
  ImGui.SetNextWindowBgAlpha(0.55)
  if ImGui.Begin("Cyberslop NCPD Uplink (pinned)", flags) then
    pcall(function()
      col(CYAN, "NCPD UPLINK · R. Jones")
      drawTransfer(d, true)
      for _, c in ipairs(d.claims) do
        if c.alive and c.bodyDead then col(RED, "  a claimed target died: dead rate") break end
      end
    end)
  end
  ImGui.End()
end)

return Up

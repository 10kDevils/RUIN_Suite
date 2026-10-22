-- A small layout engine that stands in for WoW's frame API, so RUIN's pages
-- can be built outside the game and drawn to a picture (see render.lua).
-- It resolves anchors and sizes the way the game does (closely enough to see
-- overlaps, clutter and colors), and dumps every visible region.
local F = {}

local SCREEN_W, SCREEN_H = 1600, 900

local FONTS = {
    GameFontNormal        = { size = 12, color = { 1, 0.82, 0 } },
    GameFontNormalSmall   = { size = 10, color = { 1, 0.82, 0 } },
    GameFontNormalLarge   = { size = 16, color = { 1, 0.82, 0 } },
    GameFontNormalHuge    = { size = 20, color = { 1, 0.82, 0 } },
    GameFontHighlight     = { size = 12, color = { 1, 1, 1 } },
    GameFontHighlightSmall= { size = 10, color = { 1, 1, 1 } },
    GameFontHighlightLarge= { size = 16, color = { 1, 1, 1 } },
    GameFontDisable       = { size = 12, color = { 0.5, 0.5, 0.5 } },
    GameFontDisableSmall  = { size = 10, color = { 0.5, 0.5, 0.5 } },
    ChatFontNormal        = { size = 13, color = { 1, 1, 1 } },
}
F.FONTS = FONTS

local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local pass = 0           -- bumps whenever layout may have changed
local all = {}           -- every frame, in creation order

local methods = {}
local meta = { __index = function(t, k)
    local m = methods[k]
    if m then return m end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end }

local function new(kind, parent)
    local o = setmetatable({ _type = kind, _parent = parent, _points = {}, _shown = true, _alpha = 1,
                             _regions = {}, _children = {}, _scripts = {}, _events = {} }, meta)
    if parent and parent._regions then
        if kind == "Texture" or kind == "FontString" then
            table.insert(parent._regions, o)
        else
            table.insert(parent._children, o)
        end
    end
    pass = pass + 1
    return o
end

---------------------------------------------------------------------------
-- Text measuring
---------------------------------------------------------------------------
local function plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "WW"):gsub("|A.-|a", "WW"):gsub("|n", "\n")
    return s
end

local function lineWidth(line, size)
    -- Friz Quadrata runs a little wide; capitals and digits more so.
    local w = 0
    for ch in line:gmatch(".") do
        local b = ch:byte()
        if b >= 128 then w = w + 0.25
        elseif ch:match("[A-Z0-9MW@%%]") then w = w + 0.66
        elseif ch:match("[iljI%.,:;'!|]") then w = w + 0.30
        elseif ch == " " then w = w + 0.30
        else w = w + 0.54 end
    end
    return w * size
end
F.lineWidth = lineWidth

local function textSize(fs, maxW)
    local s = plain(fs._text)
    local size = fs._size or 12
    if s == "" then return 0, 0 end
    local lines, widest = 0, 0
    for raw in (s .. "\n"):gmatch("(.-)\n") do
        local w = lineWidth(raw, size)
        if maxW and maxW > 0 and fs._wrap ~= false and w > maxW + 0.5 then
            lines = lines + math.ceil(w / maxW)
            widest = maxW
        else
            lines = lines + 1
            if w > widest then widest = w end
        end
    end
    return widest, lines * (size + 2 + (fs._spacing or 0))
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local UIParent

local function anchorXY(rect, point)
    local x = point:find("LEFT") and rect.l or point:find("RIGHT") and rect.r or (rect.l + rect.r) / 2
    local y = point:find("TOP") and rect.t or point:find("BOTTOM") and rect.b or (rect.t + rect.b) / 2
    return x, y
end

local resolve

local function explicitW(o)
    if o._w then return o._w end
    if o._type == "FontString" then
        local w = textSize(o)
        return w
    end
    return nil
end

function resolve(o)
    if o == UIParent then return { l = 0, r = SCREEN_W, t = SCREEN_H, b = 0 } end
    if o._cachePass == pass then return o._cache end
    o._cachePass = pass
    o._cache = nil
    local pts = o._points
    if #pts == 0 then return nil end
    local L, R, CX, T, B, CY
    for _, p in ipairs(pts) do
        local rel = p.rel or o._parent or UIParent
        local rr = resolve(rel)
        if not rr then return nil end
        local ax, ay = anchorXY(rr, p.rp)
        ax, ay = ax + (p.x or 0), ay + (p.y or 0)
        local pt = p.p
        if pt:find("LEFT") then L = ax elseif pt:find("RIGHT") then R = ax else CX = ax end
        if pt:find("TOP") then T = ay elseif pt:find("BOTTOM") then B = ay else CY = ay end
    end
    local l, r, t, b
    if L and R then l, r = L, R
    else
        local w = explicitW(o)
        if o._type == "FontString" and L and not R and not o._w then w = explicitW(o) end
        w = w or 0
        if L then l, r = L, L + w elseif R then l, r = R - w, R elseif CX then l, r = CX - w / 2, CX + w / 2 end
    end
    if not l then return nil end
    if T and B then t, b = T, B
    else
        local h = o._h
        if o._type == "FontString" and not h then
            local _, th = textSize(o, r - l)
            h = th
        end
        h = h or 0
        if T then t, b = T, T - h elseif B then t, b = B + h, B elseif CY then t, b = CY + h / 2, CY - h / 2 end
    end
    if not t then return nil end
    o._cache = { l = l, r = r, t = t, b = b }
    return o._cache
end
F.resolve = resolve

local function visible(o)
    while o do
        if o == UIParent then return true end
        if not o._shown then return false end
        o = o._parent
    end
    return true
end

local function fireShow(o)
    if o._scripts.OnShow then
        local ok, err = pcall(o._scripts.OnShow, o)
        if not ok then F.errors[#F.errors + 1] = "OnShow: " .. tostring(err) end
    end
    for _, c in ipairs(o._children) do if c._shown then fireShow(c) end end
end
F.errors = {}

---------------------------------------------------------------------------
-- Methods shared by frames and regions
---------------------------------------------------------------------------
local function normPoint(self, point, rel, rp, x, y)
    if type(rel) == "number" then rel, rp, x, y = nil, nil, rel, rp end
    if type(rel) == "string" then rel = F.env and F.env[rel] end
    if type(rp) == "number" then rp, x, y = nil, rp, x end
    return { p = point, rel = rel, rp = rp or point, x = x or 0, y = y or 0 }
end

function methods:SetPoint(point, rel, rp, x, y)
    local p = normPoint(self, point, rel, rp, x, y)
    for i, q in ipairs(self._points) do if q.p == p.p then self._points[i] = p; pass = pass + 1; return end end
    table.insert(self._points, p)
    pass = pass + 1
end
function methods:ClearAllPoints() self._points = {}; pass = pass + 1 end
function methods:SetAllPoints(rel)
    rel = rel or self._parent
    self._points = { { p = "TOPLEFT", rel = rel, rp = "TOPLEFT", x = 0, y = 0 },
                     { p = "BOTTOMRIGHT", rel = rel, rp = "BOTTOMRIGHT", x = 0, y = 0 } }
    pass = pass + 1
end
function methods:GetPoint(i)
    local p = self._points[i or 1]
    if not p then return nil end
    return p.p, p.rel, p.rp, p.x, p.y
end
function methods:GetNumPoints() return #self._points end
function methods:SetSize(w, h) self._w, self._h = w, h; pass = pass + 1 end
function methods:SetWidth(w) self._w = w; pass = pass + 1 end
function methods:SetHeight(h) self._h = h; pass = pass + 1 end
function methods:GetWidth()
    local r = resolve(self)
    if r then return r.r - r.l end
    return self._w or explicitW(self) or 0
end
function methods:GetHeight()
    local r = resolve(self)
    if r then return r.t - r.b end
    return self._h or 0
end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
function methods:GetRect()
    local r = resolve(self)
    if not r then return nil end
    return r.l, r.b, r.r - r.l, r.t - r.b
end
function methods:GetLeft() local r = resolve(self); return r and r.l end
function methods:GetTop() local r = resolve(self); return r and r.t end
function methods:GetCenter() local r = resolve(self); if r then return (r.l + r.r) / 2, (r.t + r.b) / 2 end end
function methods:Show()
    local was = visible(self)
    self._shown = true
    pass = pass + 1
    if not was and visible(self) then fireShow(self) end
end
function methods:Hide()
    local was = visible(self)
    self._shown = false
    pass = pass + 1
    if was and self._scripts.OnHide then pcall(self._scripts.OnHide, self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self._shown end
function methods:IsVisible() return visible(self) end
function methods:SetAlpha(a) self._alpha = a end
function methods:GetAlpha() return self._alpha end
function methods:SetScale(s) self._scale = s end
function methods:GetScale() return self._scale or 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetParent() return self._parent end
function methods:SetParent(p)
    local old = self._parent
    if old then
        local list = (self._type == "Texture" or self._type == "FontString") and old._regions or old._children
        for i, x in ipairs(list) do if x == self then table.remove(list, i) break end end
    end
    self._parent = p
    if p then
        local list = (self._type == "Texture" or self._type == "FontString") and p._regions or p._children
        table.insert(list, self)
    end
    pass = pass + 1
end
function methods:GetObjectType() return self._type end
function methods:IsObjectType(t) return self._type == t end
function methods:GetName() return self._name end
function methods:SetDrawLayer(layer, sub) self._layer, self._sub = layer, sub end

-- scripts and events
function methods:SetScript(k, f) self._scripts[k] = f end
function methods:GetScript(k) return self._scripts[k] end
function methods:HookScript(k, f)
    local prev = self._scripts[k]
    self._scripts[k] = function(...) if prev then prev(...) end f(...) end
end
function methods:HasScript() return true end
function methods:RegisterEvent(e) self._events[e] = true end
function methods:UnregisterEvent(e) self._events[e] = nil end
function methods:UnregisterAllEvents() self._events = {} end
function methods:IsEventRegistered(e) return self._events[e] end
function methods:GetFrameLevel() return self._level or 1 end
function methods:SetFrameLevel(l) self._level = l end
function methods:SetFrameStrata(s) self._strata = s end
function methods:GetFrameStrata() return self._strata or "MEDIUM" end
function methods:SetClipsChildren(v) self._clip = v end
function methods:IsMouseOver() return false end
function methods:IsEnabled() return not self._disabled end
function methods:Enable() self._disabled = false; if self._scripts.OnEnable then self._scripts.OnEnable(self) end end
function methods:Disable() self._disabled = true; if self._scripts.OnDisable then self._scripts.OnDisable(self) end end
function methods:SetEnabled(v) if v then self:Enable() else self:Disable() end end

-- child regions
function methods:CreateTexture(name, layer, template, sub)
    local t = new("Texture", self)
    t._layer, t._sub = layer or "ARTWORK", sub or 0
    if name and F.env then F.env[name] = t end
    return t
end
function methods:CreateFontString(name, layer, template)
    local fs = new("FontString", self)
    fs._layer = layer or "OVERLAY"
    fs._text = ""
    local f = template and FONTS[template]
    fs._size = f and f.size or 12
    fs._color = f and { f.color[1], f.color[2], f.color[3], 1 } or { 1, 0.82, 0, 1 }
    fs._fontObj = template
    if name and F.env then F.env[name] = fs end
    return fs
end
function methods:CreateMaskTexture() return new("Mask", nil) end
function methods:CreateAnimationGroup()
    local g = setmetatable({}, { __index = function() return function() return setmetatable({}, { __index = function() return function() end end }) end end })
    return g
end

-- textures
function methods:SetColorTexture(r, g, b, a) self._color = { r, g, b, a or 1 }; self._tex = nil; self._grad = nil end
function methods:SetTexture(path)
    if type(path) == "number" or type(path) == "string" then self._tex = path; self._color = nil end
end
function methods:GetTexture() return self._tex end
function methods:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a or 1 } end
function methods:SetGradient(dir, c1, c2)
    self._grad = { dir = dir, c1 = c1, c2 = c2 }
end
function methods:SetRotation(r) self._rot = r end
function methods:SetMask(path) self._round = path and tostring(path):find("Portrait") and true or false end
function methods:SetTexCoord() end
function methods:SetBlendMode() end

-- font strings
function methods:SetText(t)
    if self._type == "FontString" or self._type == "EditBox" then
        self._text = t and tostring(t) or ""
        pass = pass + 1
        if self._type == "EditBox" and self._scripts.OnTextChanged then pcall(self._scripts.OnTextChanged, self, false) end
    elseif self._fs then
        self._fs:SetText(t)
    elseif self._type == "Button" or self._type == "CheckButton" then
        self._fs = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self._fs:SetPoint("CENTER")
        self._fs:SetText(t)
    end
end
function methods:GetText()
    if self._type == "FontString" or self._type == "EditBox" then return self._text end
    return self._fs and self._fs._text or nil
end
function methods:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
function methods:SetTextColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function methods:GetTextColor() local c = self._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function methods:SetFont(path, size) self._size = size or self._size; pass = pass + 1; return true end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF", self._size or 12, "" end
function methods:SetFontObject(obj)
    local name = type(obj) == "table" and obj._fontName or obj
    local f = name and FONTS[name]
    if f then
        self._size = f.size
        if not self._colorSet then self._color = { f.color[1], f.color[2], f.color[3], 1 } end
        self._fontObj = name
    end
    pass = pass + 1
end
function methods:SetJustifyH(j) self._jh = j end
function methods:SetJustifyV(j) self._jv = j end
function methods:SetWordWrap(v) self._wrap = v end
function methods:SetNonSpaceWrap() end
function methods:SetSpacing(s) self._spacing = s end
function methods:SetMaxLines(n) self._maxLines = n end
function methods:GetStringWidth() local w = textSize(self); return w end
function methods:GetUnboundedStringWidth() local w = textSize(self); return w end
function methods:GetStringHeight()
    local r = resolve(self)
    local _, h = textSize(self, r and (r.r - r.l) or self._w)
    return h
end
function methods:SetShadowOffset() end
function methods:SetShadowColor() end
function methods:IsTruncated() return false end

-- buttons
function methods:SetFontString(fs) self._fs = fs end
function methods:GetFontString() return self._fs end
function methods:SetNormalFontObject() end
function methods:SetHighlightFontObject() end
function methods:SetDisabledFontObject() end
function methods:SetChecked(v) self._checked = v and true or false end
function methods:GetChecked() return self._checked end
function methods:SetCheckedTexture(t)
    if type(t) == "table" then self._checkedTex = t; t._checkedOnly = true end
end
function methods:SetNormalTexture(t) if type(t) == "table" then self._normalTex = t end end
function methods:SetHighlightTexture(t) if type(t) == "table" then t._layer = "HIGHLIGHT" end end
function methods:SetPushedTexture(t) if type(t) == "table" then t._layer = "HIGHLIGHT" end end
function methods:SetDisabledCheckedTexture(t) if type(t) == "table" then t._layer = "HIGHLIGHT" end end
function methods:Click(button)
    if self._type == "CheckButton" then self._checked = not self._checked end
    if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end
end

-- edit boxes
function methods:SetFocus() self._focus = true end
function methods:ClearFocus() self._focus = false end
function methods:HasFocus() return self._focus end
function methods:SetNumber(n) self:SetText(tostring(n)) end
function methods:GetNumber() return tonumber(self._text) or 0 end
function methods:SetTextInsets(l, r) self._inset = l end

-- scroll frames
function methods:SetScrollChild(c)
    self._scrollChild = c
    c:SetParent(self)
    c._points = { { p = "TOPLEFT", rel = self, rp = "TOPLEFT", x = 0, y = 0 } }
    pass = pass + 1
end
function methods:GetScrollChild() return self._scrollChild end
function methods:GetVerticalScroll() return 0 end
function methods:SetVerticalScroll() end
function methods:UpdateScrollChildRect() end
function methods:GetVerticalScrollRange() return 0 end

---------------------------------------------------------------------------
-- CreateFrame with the templates RUIN uses
---------------------------------------------------------------------------
local function applyTemplate(f, template)
    if not template then return end
    if template:find("UICheckButtonTemplate") then
        f:SetSize(26, 26)
        f._blizzCheck = true
    elseif template:find("InputBoxTemplate") then
        f._blizzInput = true
    elseif template:find("UIPanelScrollFrameTemplate") then
        f._scrollBar = true
    end
end

function F.install(env, client)
    F.env = env
    pass = pass + 1
    UIParent = new("Frame", nil)
    UIParent._name = "UIParent"
    env.UIParent = UIParent
    F.UIParent = UIParent
    for name, f in pairs(FONTS) do env[name] = { _fontName = name, GetFont = function() return "x", f.size end } end
    env.CreateFrame = function(kind, name, parent, template)
        local f = new(kind or "Frame", parent or UIParent)
        if kind == "EditBox" then f._text = "" end
        f._name = name
        applyTemplate(f, template)
        all[#all + 1] = f
        if client then table.insert(client.frames, f) end
        if name then env[name] = f end
        return f
    end
    env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
    env.GameFontNormal = env.GameFontNormal
    return UIParent
end

---------------------------------------------------------------------------
-- Dump: every visible region with screen rectangles (y down), in draw order
---------------------------------------------------------------------------
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, TOOLTIP = 7 }

local function rect(o)
    local r = resolve(o)
    if not r then return nil end
    return { x = r.l, y = SCREEN_H - r.t, w = r.r - r.l, h = r.t - r.b }
end

local function intersect(a, b)
    if not a then return b end
    if not b then return a end
    local x1, y1 = math.max(a.x, b.x), math.max(a.y, b.y)
    local x2, y2 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
    return { x = x1, y = y1, w = math.max(0, x2 - x1), h = math.max(0, y2 - y1) }
end

function F.Dump(root)
    local out = {}
    local function region(o, alpha, clip)
        if not o._shown then return end
        local r = rect(o)
        if not r then return end
        if o._layer == "HIGHLIGHT" then return end
        if o._checkedOnly then
            local owner = o._parent
            if not (owner and owner._checked) then return end
        end
        local a = alpha * (o._alpha or 1)
        local e = { x = r.x, y = r.y, w = r.w, h = r.h, a = a, clip = clip }
        if o._type == "Texture" then
            if o._grad then
                local g = o._grad
                e.grad = { dir = g.dir, c1 = { g.c1.r, g.c1.g, g.c1.b, g.c1.a }, c2 = { g.c2.r, g.c2.g, g.c2.b, g.c2.a } }
            end
            e.k = "t"
            e.color = o._color
            e.tex = o._tex and tostring(o._tex) or nil
            e.vertex = o._vertex
            e.rot = o._rot
            e.round = o._round
            if not e.color and not e.tex and not e.grad then return end
        else
            e.k = "s"
            e.text = o._text
            e.size = o._size
            e.color = o._color
            local single = (o._w == nil) and (#o._points < 2)
            local ap = o._points[1] and o._points[1].p or "CENTER"
            e.jh = (single and (ap:find("LEFT") and "LEFT" or ap:find("RIGHT") and "RIGHT" or "CENTER")) or o._jh or "CENTER"
            e.jv = o._jv or "MIDDLE"
            e.wrap = o._wrap ~= false
            e.explicitW = (o._w ~= nil) or (#o._points >= 2)
            if not e.text or e.text == "" then return end
        end
        out[#out + 1] = e
    end
    local deferred = {}
    local function frame(f, alpha, clip, depth)
        if not f._shown then return end
        local a = alpha * (f._alpha or 1)
        local r = rect(f)
        if f._clip or f._type == "ScrollFrame" then
            if r then clip = intersect(clip, r) end
        end
        -- Blizzard templates the kit still uses
        if r and f._blizzCheck then
            out[#out + 1] = { k = "chk", x = r.x + 3, y = r.y + 3, w = r.w - 6, h = r.h - 6, a = a, on = f._checked, clip = clip }
        elseif r and f._blizzInput then
            out[#out + 1] = { k = "inp", x = r.x - 5, y = r.y, w = r.w + 5, h = r.h, a = a, clip = clip }
        end
        local regs = {}
        for i, o in ipairs(f._regions) do regs[#regs + 1] = { o = o, i = i } end
        table.sort(regs, function(p, q)
            local lp, lq = LAYERS[p.o._layer] or 3, LAYERS[q.o._layer] or 3
            if lp ~= lq then return lp < lq end
            if (p.o._sub or 0) ~= (q.o._sub or 0) then return (p.o._sub or 0) < (q.o._sub or 0) end
            return p.i < q.i
        end)
        for _, p in ipairs(regs) do region(p.o, a, clip) end
        if f._type == "EditBox" and r and (f._text or "") ~= "" then
            out[#out + 1] = { k = "s", x = r.x + (f._inset or 0) + 1, y = r.y, w = r.w - (f._inset or 0) - 2, h = r.h,
                              text = f._text, size = 12, color = { 1, 1, 1, 1 }, jh = "LEFT", jv = "MIDDLE",
                              wrap = false, explicitW = true, a = a, clip = clip }
        end
        local kids = {}
        for i, c in ipairs(f._children) do kids[#kids + 1] = { c = c, i = i } end
        table.sort(kids, function(p, q)
            local sp, sq = STRATA[p.c._strata or ""] or 0, STRATA[q.c._strata or ""] or 0
            if sp ~= sq then return sp < sq end
            if (p.c._level or 0) ~= (q.c._level or 0) then return (p.c._level or 0) < (q.c._level or 0) end
            return p.i < q.i
        end)
        for _, k in ipairs(kids) do
            -- a child in a higher strata than the window (a dropdown list) draws over everything, like the game
            if depth > 0 and (STRATA[k.c._strata or ""] or 0) >= (STRATA.DIALOG or 99) then
                deferred[#deferred + 1] = { c = k.c, a = a }
            else
                frame(k.c, a, clip, depth + 1)
            end
        end
        if f._scrollBar and r then
            local child = f._scrollChild
            local cr = child and rect(child)
            if cr and cr.h > r.h + 1 then
                out[#out + 1] = { k = "bar", x = r.x + r.w + 4, y = r.y, w = 14, h = r.h, a = a, frac = r.h / cr.h }
            end
        end
    end
    frame(root or UIParent, 1, nil, 0)
    local i = 1
    while deferred[i] do frame(deferred[i].c, deferred[i].a, nil, 1); i = i + 1 end
    return out
end

-- Minimal JSON encoder for the dump.
local function enc(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return string.format("%.3f", v):gsub("%.?0+$", "")
    end
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            if c == "\n" then return "\\n" end
            if c == '"' then return '\\"' end
            if c == "\\" then return "\\\\" end
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = enc(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do
            if type(k) == "string" then parts[#parts + 1] = enc(k) .. ":" .. enc(x) end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
F.json = enc
F.SCREEN_W, F.SCREEN_H = SCREEN_W, SCREEN_H

return F

--!nonstrict

local Workspace = game:GetService("Workspace")

local Debug = {}
Debug.__index = Debug

local COLORS = {
	visible = Color3.fromRGB(60, 255, 90),
	blocked = Color3.fromRGB(255, 60, 60),
	search = Color3.fromRGB(255, 225, 0),
	ghost = Color3.fromRGB(255, 255, 255),
	noise = Color3.fromRGB(0, 230, 255),
	hearing = Color3.fromRGB(70, 110, 255),
	path = Color3.fromRGB(180, 130, 255),
	pathCurrent = Color3.fromRGB(255, 255, 255),
	gap = Color3.fromRGB(200, 60, 255),
}

local function newPart(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Debug.new(config)
	local folder = Workspace:FindFirstChild("NPCSystemDebug")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "NPCSystemDebug"
		folder.Parent = Workspace
	end
	return setmetatable({
		cfg = config.debug,
		enabled = false,
		folder = folder,
		pool = {},
		timed = {},
		live = 0,
		dropped = 0,
		per = {},
	}, Debug)
end

function Debug:_acquire(): Part?
	if self.live >= self.cfg.maxVisualParts then
		self.dropped += 1
		return nil
	end
	local p = table.remove(self.pool) or newPart()
	p.Shape = Enum.PartType.Block
	p.Transparency = 0
	p.Material = Enum.Material.Neon
	self.live += 1
	p.Parent = self.folder
	return p
end

function Debug:_release(p: Part)
	p.Parent = nil
	p.Name = "Part"
	self.live -= 1
	if #self.pool < 400 then
		table.insert(self.pool, p)
	else
		p:Destroy()
	end
end

function Debug:_line(a: Vector3, b: Vector3, color: Color3, thickness: number, life: number): Part?
	local p = self:_acquire()
	if not p then
		return nil
	end
	local len = (b - a).Magnitude
	if len < 0.02 then
		len = 0.02
		b = a + Vector3.new(0, 0, 0.02)
	end
	p.Size = Vector3.new(thickness, thickness, len)
	p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
	p.Color = color
	table.insert(self.timed, { part = p, expires = os.clock() + life })
	return p
end

function Debug:_ball(pos: Vector3, diameter: number, color: Color3, transparency: number, life: number): Part?
	local p = self:_acquire()
	if not p then
		return nil
	end
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = CFrame.new(pos)
	p.Color = color
	p.Transparency = transparency
	table.insert(self.timed, { part = p, expires = os.clock() + life })
	return p
end

function Debug:setEnabled(on: boolean)
	if on == self.enabled then
		return
	end
	self.enabled = on
	if not on then
		self:clear()
	end
end

function Debug:clear()
	for _, t in ipairs(self.timed) do
		self:_release(t.part)
	end
	table.clear(self.timed)
	for ctrl in pairs(self.per) do
		self:removeController(ctrl)
	end
	self.dropped = 0
	self.folder:ClearAllChildren()
	for _, p in ipairs(self.pool) do
		p:Destroy()
	end
	table.clear(self.pool)
	self.live = 0
end

function Debug:stats()
	return { live = self.live, pooled = #self.pool, timed = #self.timed, dropped = self.dropped, folderChildren = #self.folder:GetChildren() }
end

function Debug:addVisionRays(ctrl, rays)
	if not (self.enabled and self.cfg.showVisionRays) then
		return
	end
	local life = self.cfg.rayLifetime
	local rec = self:_rec(ctrl)
	rec.blockers = {}
	for _, r in ipairs(rays) do
		local part = self:_line(r.from, r.to, if r.visible then COLORS.visible else COLORS.blocked, 0.06, life)
		if r.blockedBy then
			if #rec.blockers < 4 then
				table.insert(rec.blockers, r.blockedBy.Name)
			end
			if part then
				part:SetAttribute("BlockedBy", r.blockedBy:GetFullName())
			end
		elseif not r.visible and part then
			part:SetAttribute("BlockedBy", "(no impact)")
		end
		if part then
			part:SetAttribute("Sample", r.sample)
		end
	end
end

function Debug:addSearchRays(ctrl, rays)
	if not (self.enabled and self.cfg.showSearchRays) then
		return
	end
	for _, r in ipairs(rays) do
		local part = self:_line(r.from, r.to, COLORS.search, 0.05, self.cfg.rayLifetime * 4)
		if part and r.blockedBy then
			part:SetAttribute("BlockedBy", r.blockedBy:GetFullName())
		end
	end
end

function Debug:addNoise(event)
	if not (self.enabled and self.cfg.showNoise) then
		return
	end

	local styles = self.cfg.noiseStyle
	local style = (event.tag and styles and styles[event.tag]) or (styles and styles.default) or { color = COLORS.noise, lifetime = self.cfg.noiseLifetime }
	local sphere = self:_ball(event.position, math.max(event.radius * 2, 0.2), style.color, 0.88, style.lifetime)
	if sphere then
		sphere.Name = "Noise_" .. tostring(event.tag or "manual")
	end
	self:_ball(event.position, 1.2, style.color, 0, style.lifetime)
end

function Debug:addGapRays(ctrl, rays)
	if not (self.enabled and self.cfg.showGaps) then
		return
	end
	for _, r in ipairs(rays) do
		self:_line(r.from, r.to, COLORS.gap, 0.04, 0.3)
	end
end

function Debug:_rec(ctrl)
	local rec = self.per[ctrl]
	if not rec then
		rec = { ghostVersion = -1, pathSig = "", blockers = {}, labelAt = 0 }
		self.per[ctrl] = rec
	end
	return rec
end

local function destroyIf(inst)
	if inst then
		inst:Destroy()
	end
end

function Debug:removeController(ctrl)
	local rec = self.per[ctrl]
	if not rec then
		return
	end
	destroyIf(rec.ghost)
	destroyIf(rec.pathFolder)
	destroyIf(rec.labelPart)
	destroyIf(rec.hearing)
	destroyIf(rec.gapFolder)
	self.per[ctrl] = nil
end

local function fmt(v: Vector3?): string
	if not v then
		return "-"
	end
	return ("(%.0f, %.0f, %.0f)"):format(v.X, v.Y, v.Z)
end

function Debug:_updateGhost(ctrl, rec)
	local v = ctrl.visual

	local want = self.cfg.showLastSeenGhost and v ~= nil and v.visible == false and v.pose ~= nil
	if not want then
		if rec.ghost then
			rec.ghost:Destroy()
			rec.ghost = nil
			rec.ghostVersion = -1
		end
		return
	end
	if rec.ghost and rec.ghostVersion == v.poseVersion then
		return
	end
	destroyIf(rec.ghost)
	local model = Instance.new("Model")
	model.Name = ("LastSeenGhost_%d_%d"):format(ctrl.id, v.player.UserId)
	for _, entry in ipairs(v.pose) do
		local p = newPart()
		p.Name = entry.name
		p.Material = Enum.Material.SmoothPlastic
		p.Color = COLORS.ghost
		p.Transparency = 0.55
		p.Size = entry.size
		p.CFrame = entry.cframe
		p.Parent = model
	end
	model.Parent = self.folder
	rec.ghost = model
	rec.ghostVersion = v.poseVersion
end

function Debug:_updatePath(ctrl, rec)
	local nav = ctrl.nav
	local wps = nav.waypoints
	if not (self.cfg.showPaths and wps and nav.status == "Moving") then
		if rec.pathFolder then
			rec.pathFolder:Destroy()
			rec.pathFolder = nil
			rec.pathSig = ""
		end
		return
	end
	local sig = nav.pathVersion .. ":" .. nav.wpIndex
	if sig == rec.pathSig then
		return
	end
	rec.pathSig = sig
	destroyIf(rec.pathFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Path_" .. ctrl.id
	local up = Vector3.new(0, 0.6, 0)
	for i = math.max(1, nav.wpIndex - 1), #wps do
		local p = newPart()
		p.Shape = Enum.PartType.Ball
		local current = i == nav.wpIndex
		local d = if current then 1.1 else 0.55
		p.Size = Vector3.new(d, d, d)
		p.Color = if current then COLORS.pathCurrent else COLORS.path
		p.CFrame = CFrame.new(wps[i].Position + up)
		p.Parent = folder
		if i < #wps then
			local a, b = wps[i].Position + up, wps[i + 1].Position + up
			local len = math.max((b - a).Magnitude, 0.02)
			local seg = newPart()
			seg.Size = Vector3.new(0.12, 0.12, len)
			seg.CFrame = CFrame.lookAt(a, b + Vector3.new(0, 0, 0.0001)) * CFrame.new(0, 0, -len / 2)
			seg.Color = COLORS.path
			seg.Parent = folder
		end
	end
	folder.Parent = self.folder
	rec.pathFolder = folder
end

function Debug:_updateGaps(ctrl, rec)
	if not self.cfg.showGaps or #ctrl.gaps == 0 then
		if rec.gapFolder then
			rec.gapFolder:Destroy()
			rec.gapFolder = nil
			rec.gapCount = 0
		end
		return
	end
	if rec.gapCount == #ctrl.gaps and rec.gapFolder then
		return
	end
	rec.gapCount = #ctrl.gaps
	destroyIf(rec.gapFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Gaps_" .. ctrl.id
	for _, g in ipairs(ctrl.gaps) do
		local a, b = g.entry + Vector3.new(0, 0.5, 0), g.exit + Vector3.new(0, 0.5, 0)
		local len = math.max((b - a).Magnitude, 0.05)
		local seg = newPart()
		seg.Name = "KnownGap"
		seg.Size = Vector3.new(0.2, 0.2, len)
		seg.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
		seg.Color = COLORS.gap
		seg.Parent = folder
		for _, p in ipairs({ a, b }) do
			local ball = newPart()
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(0.9, 0.9, 0.9)
			ball.Color = COLORS.gap
			ball.CFrame = CFrame.new(p)
			ball.Parent = folder
		end
	end
	folder.Parent = self.folder
	rec.gapFolder = folder
end

function Debug:_updateLabel(ctrl, rec, now: number)
	if not self.cfg.showState then
		destroyIf(rec.labelPart)
		rec.labelPart = nil
		return
	end
	if not rec.labelPart then
		local part = newPart()
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(300, 150)
		gui.StudsOffset = Vector3.new(0, 1.5, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.55
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 13
		label.Font = Enum.Font.Code
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Parent = gui
		gui.Parent = part
		part.Parent = self.folder
		rec.labelPart, rec.label = part, label
	end
	rec.labelPart.CFrame = CFrame.new(ctrl.root.Position + Vector3.new(0, 5, 0))
	if now - rec.labelAt < self.cfg.labelRefreshInterval then
		return
	end
	rec.labelAt = now
	local nav, v, n = ctrl.nav, ctrl.visual, ctrl.noise
	local lines = {
		("%s #%d [%s]"):format(ctrl.model.Name, ctrl.id, ctrl.state),
		"reason: " .. ctrl.stateReason,
		("target: %s %s"):format(if v then v.player.Name else "-", if v then (if v.visible then "(visible)" else "(lost)") else ""),
		("dest req %s nav %s%s"):format(fmt(nav.requested), fmt(nav.destination), if nav.usedAlternate then " [alt]" else ""),
		("nav %s attempts %d/%d repath: %s"):format(nav.status, nav.attempts, ctrl.config.navigation.maxRecoveryAttempts, tostring(nav.lastRepathReason)),
		("note: %s"):format(tostring(nav.lastRecoveryNote or nav.failReason or "-")),
		("noise q=%d heard=%d grp=%d rej=%d exp=%d ign=%d"):format(#n.queue, n.stats.heard, n.stats.grouped, n.stats.rejected, n.stats.expired, n.stats.ignored),
		("blockers: %s"):format(table.concat(rec.blockers, ",")),
		("gaps known: %d  squeeze: %s"):format(#ctrl.gaps, if ctrl.squeeze then ctrl.squeeze.stage else "-"),
		("dropped visuals: %d"):format(self.dropped),
	}
	rec.label.Text = table.concat(lines, "\n")
end

function Debug:_updateHearing(ctrl, rec)
	if not self.cfg.showHearingRange or ctrl.profile.hearing <= 0 then
		destroyIf(rec.hearing)
		rec.hearing = nil
		return
	end
	if not rec.hearing then
		local p = newPart()
		p.Shape = Enum.PartType.Ball
		p.Color = COLORS.hearing
		p.Transparency = 0.93
		local d = ctrl.profile.hearing * 2
		p.Size = Vector3.new(d, d, d)
		p.Name = "HearingRange"
		p.Parent = self.folder
		rec.hearing = p
	end
	rec.hearing.CFrame = CFrame.new(ctrl.root.Position)
end

function Debug:update(controllers: { any })
	if not self.enabled then
		return
	end
	local now = os.clock()

	local timed = self.timed
	local i = 1
	while i <= #timed do
		local t = timed[i]
		if t.expires <= now then
			self:_release(t.part)
			timed[i] = timed[#timed]
			timed[#timed] = nil
		else
			i += 1
		end
	end

	for _, ctrl in ipairs(controllers) do
		if ctrl:isActive() then
			local rec = self:_rec(ctrl)
			self:_updateGhost(ctrl, rec)
			self:_updatePath(ctrl, rec)
			self:_updateGaps(ctrl, rec)
			self:_updateLabel(ctrl, rec, now)
			self:_updateHearing(ctrl, rec)
		end
	end
end

return Debug

--- @since 26.5.6
-- gm — флешки и телефон: выбрать, смонтировать при необходимости и открыть
-- gu — отмонтировать / извлечь

local HOME = os.getenv("HOME") or "/"
local RUNTIME = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. ya.uid())

local function notify(msg, level)
	ya.notify { title = "Devices", content = msg, timeout = 5, level = level or "info" }
end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

local get_cwd = ya.sync(function() return tostring(cx.active.current.cwd) end)

-- съёмные разделы (флешки, SD-карты, внешние диски)
local function drives()
	local out = Command("lsblk")
		:arg({ "-J", "-p", "-o", "NAME,LABEL,SIZE,FSTYPE,MOUNTPOINT,HOTPLUG,RM,TYPE,MODEL" })
		:output()
	local t = out and ya.json_decode(out.stdout) or {}
	local list = {}

	local function walk(dev, parent)
		local removable = dev.hotplug == true or dev.rm == true
			or (parent and (parent.hotplug == true or parent.rm == true))
		local leaf = dev.type == "part" or (dev.type == "disk" and not dev.children)
		if removable and leaf and str(dev.fstype) then
			list[#list + 1] = {
				kind = "drive",
				dev = dev.name,
				mount = str(dev.mountpoint),
				name = str(dev.label) or str(parent and parent.model) or str(dev.model) or dev.name,
				size = str(dev.size) or "",
			}
		end
		for _, c in ipairs(dev.children or {}) do walk(c, dev) end
	end

	for _, d in ipairs(t.blockdevices or {}) do walk(d, nil) end
	return list
end

-- телефоны по MTP через gvfs
local function phones()
	local out = Command("gio"):arg({ "mount", "-li" }):output()
	local list, seen, name = {}, {}, nil
	for line in (out and out.stdout or ""):gmatch("[^\n]+") do
		name = line:match("^%s*Volume%(%d+%):%s*(.+)$") or name
		local uri = line:match("activation_root=(mtp://%S+)")
		if uri and not seen[uri] then
			seen[uri] = true
			list[#list + 1] = { kind = "phone", uri = uri, name = name or "Phone" }
		end
	end
	return list
end

-- путь смонтированного телефона в ~/../gvfs
local function phone_path(p)
	local host = p.uri:match("^mtp://([^/]+)")
	local out = Command("sh")
		:arg({ "-c", 'ls -d "$1"/mtp:host=* 2>/dev/null', "sh", RUNTIME .. "/gvfs" })
		:output()
	local first
	for dir in (out and out.stdout or ""):gmatch("[^\n]+") do
		first = first or dir
		if host and dir:find(host, 1, true) then return dir end
	end
	return first
end

local function label(d)
	if d.kind == "phone" then
		return string.format("󰄜  %s", d.name)
	end
	return string.format("󰕓  %s  %s%s", d.name, d.size, d.mount and ("  →  " .. d.mount) or "")
end

local function choose(list)
	local cands = {}
	for i, d in ipairs(list) do
		cands[i] = { on = tostring(i), desc = label(d) }
	end
	return list[ya.which { cands = cands, silent = false }]
end

local function open(d)
	if d.kind == "drive" then
		local path = d.mount
		if not path then
			local out, err = Command("udisksctl"):arg({ "mount", "-b", d.dev }):output()
			if not out or not out.status.success then
				return notify("Mount failed: " .. (out and out.stderr or tostring(err)), "error")
			end
			path = out.stdout:match(" at (.-)%.?%s*$")
		end
		if path then ya.emit("cd", { path }) end
	else
		local out = Command("gio"):arg({ "mount", d.uri }):output()
		local path = phone_path(d)
		if not path then
			local msg = out and out.stderr or ""
			return notify("Can't open phone. Unlock it and choose «File transfer» in the USB menu.\n" .. msg, "warn")
		end
		ya.emit("cd", { path })
	end
end

local function close(d)
	local cwd = get_cwd()
	local root = d.kind == "drive" and d.mount or phone_path(d)
	if root and cwd:sub(1, #root) == root then
		ya.emit("cd", { HOME })
	end

	local out
	if d.kind == "drive" then
		out = Command("udisksctl"):arg({ "unmount", "-b", d.dev }):output()
		if out and out.status.success then
			Command("udisksctl"):arg({ "power-off", "-b", d.dev }):output()
		end
	else
		out = Command("gio"):arg({ "mount", "-u", d.uri }):output()
	end

	if out and out.status.success then
		notify(d.name .. " can be safely removed")
	else
		notify("Unmount failed: " .. (out and out.stderr or ""), "error")
	end
end

return {
	entry = function(_, job)
		local unmount = job.args[1] == "unmount"
		local list = {}

		for _, d in ipairs(drives()) do
			if not unmount or d.mount then list[#list + 1] = d end
		end
		for _, p in ipairs(phones()) do
			if not unmount or phone_path(p) then list[#list + 1] = p end
		end

		if #list == 0 then
			return notify(unmount and "Nothing mounted"
				or "No drives or phone found.\nPhone: connect USB, unlock it and choose «File transfer».", "warn")
		end

		local d = choose(list)
		if not d then return end
		if unmount then close(d) else open(d) end
	end,
}

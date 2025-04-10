local M = {}

-- Constants
M.GITHUB_RAW_URL = "https://raw.githubusercontent.com/thiagobodruk/bible/master/json"
M.GITHUB_API_URL = "https://api.github.com/repos/thiagobodruk/bible/contents/json"

---Get the data directory path
---@return string data_dir
function M.get_data_dir()
	local xdg_data = vim.fn.stdpath("data")
	local data_dir = xdg_data .. "/bible-reader/data"
	return data_dir
end

---Ensure the data directory exists
---@return boolean success
function M.ensure_data_dir()
	local data_dir = M.get_data_dir()
	return vim.fn.mkdir(data_dir, "p") ~= 0
end

---Download a file using curl if available, otherwise use vim.uv
---@param url string The URL to download from
---@param output_path string The path to save the file
---@return boolean success
---@return string? error
function M.download_file(url, output_path)
	-- First try using vim.uv (libuv)
	local function download_with_libuv()
		local client = vim.uv.new_tcp()
		if not client then
			vim.notify("Failed to create TCP client", vim.log.levels.ERROR)
			return false, "Failed to create TCP client"
		end

		local request = string.format(
			"GET %s HTTP/1.0\r\nHost: raw.githubusercontent.com\r\n\r\n",
			url:gsub("https://raw.githubusercontent.com", "")
		)
		local response = ""
		local connected = false
		local success = false
		local error_msg

		client:connect("raw.githubusercontent.com", 443, function(err)
			if err then
				error_msg = "Connection failed: " .. err
				return
			end
			connected = true
			client:write(request)
		end)

		client:read_start(function(err, chunk)
			if err then
				error_msg = "Read failed: " .. err
				return
			end
			if chunk then
				response = response .. chunk
			else
				client:close()
				-- Extract body from HTTP response
				local body = response:match("\r\n\r\n(.+)")
				if body then
					local file = io.open(output_path, "wb")
					if file then
						file:write(body)
						file:close()
						success = true
					else
						error_msg = "Failed to write to file"
					end
				else
					error_msg = "Invalid response"
				end
			end
		end)

		-- Wait for operation to complete
		vim.wait(10000, function()
			return success or error_msg ~= nil or connected
		end)

		return success, error_msg
	end

	-- Try curl first
	local has_curl = vim.fn.executable("curl") == 1
	if has_curl then
		local command = string.format('curl -L -s "%s" -o "%s"', url, output_path)
		local ok, _, _ = os.execute(command)
		if ok then
			return true
		end
	else
		vim.notify("curl not found, using built-in download method", vim.log.levels.INFO)
	end

	-- Fallback to libuv if curl fails or is not available
	local success, err = download_with_libuv()
	if not success then
		return false, string.format("Download failed: %s", err or "unknown error")
	end

	return true
end

---Load index data from GitHub or local cache
---@return BibleLanguage[]|nil
function M.load_index_data()
	local data_dir = M.get_data_dir()
	local index_path = data_dir .. "/index.json"

	-- Try to load from local cache first
	local file = io.open(index_path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		local success, decoded = pcall(vim.json.decode, content)
		if success then
			return decoded
		end
	end

	-- If not found or invalid, download from GitHub
	if not M.ensure_data_dir() then
		return nil
	end

	local success, err = M.download_file(M.GITHUB_RAW_URL .. "/index.json", index_path)
	if not success then
		vim.notify("Failed to download index: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return nil
	end

	-- Try to load the downloaded file
	file = io.open(index_path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		local decode_success, decoded = pcall(vim.json.decode, content)
		if decode_success then
			return decoded
		end
	end

	return nil
end

return M

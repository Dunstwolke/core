dunstblick_discovery = Proto("dunst", "Dunstblick Discovery")

local message_length = ProtoField.bytes("dunst.magic", "magic", base.SPACE)
local message_type = ProtoField.uint16("dunst.type", "type", base.DEC, {
  [0] = "discover",
  [1] = "discover_response", 
})

local features = ProtoField.uint16("dunst.feature", "Features", base.HEX)
  local has_description = ProtoField.bool("dunst.feature.has_description", "has_description", 16, {}, 1)
  local has_icon = ProtoField.bool("dunst.feature.has_icon", "has_icon", 16, {}, 2)
  local requires_auth = ProtoField.bool("dunst.feature.requires_auth", "requires_auth", 16, {}, 4)
  local wants_username = ProtoField.bool("dunst.feature.wants_username", "wants_username", 16, {}, 8)
  local wants_password = ProtoField.bool("dunst.feature.wants_password", "wants_password", 16, {}, 16)
  local is_encrypted = ProtoField.bool("dunst.feature.is_encrypted", "is_encrypted", 16, {}, 32)

local tcp_port = ProtoField.uint16("dunst.tcp_port", "TCP Port", base.DEC)
local display_name = ProtoField.stringz("dunst.display_name", "Display Name", base.UNICODE)

local short_desc = ProtoField.stringz("dunst.short_desc", "App Description", base.UNICODE)

local tvg_icon = ProtoField.bytes("dunst.iconfoo", "App Icon", base.NONE)
local tvg_icon_len = ProtoField.uint16("dunst.iconfoo.len", "Size", base.DEC)
local tvg_icon_bits = ProtoField.bytes("dunst.iconfoo.bits", "Size", base.NONE)

dunstblick_discovery.fields = {
  message_length,
  message_type,
  features,
  has_description,
  has_icon,
  requires_auth,
  wants_username,
  wants_password,
  is_encrypted,
  tcp_port,
  display_name,
  short_desc,
  tvg_icon,
  tvg_icon_len,
  tvg_icon_bits,
}

function dunstblick_discovery.dissector(buffer, pinfo, tree)
  length = buffer:len()
  if length == 0 then return end

  pinfo.cols.protocol = "Dunstblick"

  local subtree = tree:add(dunstblick_discovery, buffer(), "Dunstblick Discovery")

  subtree:add_le(message_length, buffer(0,4))

  local discover_respond = subtree:add_le(message_type, buffer(4,2))
  
  local msg_type = buffer(4,2):le_uint()
  if msg_type == 1 then
    local features_tree = discover_respond:add_le(features, buffer(6,2))
    local feature_fld = buffer(6,2)
    do
      features_tree:add_le(has_description, feature_fld)
      features_tree:add_le(has_icon, feature_fld)
      features_tree:add_le(requires_auth, feature_fld)
      features_tree:add_le(wants_username, feature_fld)
      features_tree:add_le(wants_password, feature_fld)
      features_tree:add_le(is_encrypted, feature_fld)
    end

    discover_respond:add_le(tcp_port, buffer(8,2))
    discover_respond:add_le(display_name, buffer(10,64))

    local feature_int = feature_fld:le_uint()
    local offset = 74

    if bit.band(feature_int, 1) ~= 0 then
      discover_respond:add_le(short_desc, buffer(offset,256))
      offset = offset + 256
    end

    if bit.band(feature_int, 2) ~= 0 then
      local bits = buffer(offset, 514)
      local icon_tree = discover_respond:add_le(tvg_icon, bits)

      icon_tree:add_le(tvg_icon_len, bits(0,2))
      
      local len = math.min(512, bits(0,2):le_uint())
      icon_tree:add_le(tvg_icon_bits, bits(2,len))
      offset = offset + 514
    end

  end
end

local tcp_port = DissectorTable.get("udp.port")
tcp_port:add(1309, dunstblick_discovery)
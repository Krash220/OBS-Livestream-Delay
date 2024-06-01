obs = obslua
bit = require("bit")

enabled = false
delay_ms = 5000
scene_name = ""

hotkey_id = obs.OBS_INVALID_HOTKEY_ID

PROP_HOTKEY = "LIVESTREAM_DELAY_HOTKEY"
PROP_ENABLED = "LIVESTREAM_DELAY_ENABLED"
PROP_DELAY = "LIVESTREAM_DELAY_MS"
PROP_SCENE = "LIVESTREAM_DELAY_SCENE"
FILTER = "LIVESTREAM_DELAY"

timer = false

function video_filter(source)
    local filter = obs.obs_source_get_filter_by_name(source, FILTER)

    local data = obs.obs_data_create()
    obs.obs_data_set_int(data, "delay_ms", delay_ms)

    if filter ~= nil then
        obs.obs_source_update(filter, data)
    else
        filter = obs.obs_source_create_private("gpu_delay", FILTER, data)
        obs.obs_source_filter_add(source, filter)
    end

    obs.obs_source_filter_set_order(source, filter, obs.OBS_ORDER_MOVE_BOTTOM)
    obs.obs_source_release(filter)
    obs.obs_data_release(data)
end

function audio_filter(source, new_source_only)
    local filter = obs.obs_source_get_filter_by_name(source, FILTER)

    if filter ~= nil then
        if not new_source_only then
            obs.obs_source_set_async_decoupled(source, true)
            obs.obs_source_set_async_decoupled(source, false)
        end
    else
        obs.obs_source_set_sync_offset(source, obs.obs_source_get_sync_offset(source) + delay_ms * 1000000)

        data = obs.obs_data_create()
        filter = obs.obs_source_create_private("vst_filter", FILTER, data)
        obs.obs_source_filter_add(source, filter)

        obs.obs_source_set_async_decoupled(source, true)
        obs.obs_source_set_async_decoupled(source, false)
    end

    obs.obs_source_release(filter)
end

function remove_filter(source)
    local filter = obs.obs_source_get_filter_by_name(source, FILTER)

    if filter ~= nil then
        obs.obs_source_filter_remove(source, filter)
        obs.obs_source_release(filter)

        if bit.band(obs.obs_source_get_output_flags(source), obs.OBS_SOURCE_AUDIO) ~= 0 then
            obs.obs_source_set_sync_offset(source, obs.obs_source_get_sync_offset(source) - delay_ms * 1000000)
        end
    end
end

function audio_filter_recursive(scene, new_source_only)
    local items = obs.obs_scene_enum_items(scene)
    if items ~= nil then
        for _, item in ipairs(items) do
            local source = obs.obs_sceneitem_get_source(item)

            if bit.band(obs.obs_source_get_output_flags(source), obs.OBS_SOURCE_AUDIO) ~= 0 then
                audio_filter(source, new_source_only)
            elseif obs.obs_source_get_unversioned_id(source) == "scene" then
                audio_filter_recursive(obs.obs_scene_from_source(source), new_source_only)
            elseif obs.obs_source_get_unversioned_id(source) == "group" then
                audio_filter_recursive(obs.obs_group_from_source(source), new_source_only)
            end
        end
    end
    obs.sceneitem_list_release(items)
end

function livestream_cutoff()
    if enabled then
        local scene_source = obs.obs_get_source_by_name(scene_name)
        if scene_source ~= nil then
            video_filter(scene_source)

            local scene = obs.obs_scene_from_source(scene_source)

            audio_filter_recursive(scene, false)
            obs.obs_source_release(scene_source)
        end
    end
end

function source_create(cd)
	local source = obs.calldata_source(cd, "source")
	if source ~= nil and enabled then
        local scene_source = obs.obs_get_source_by_name(scene_name)
        if scene_source ~= nil then
            local scene = obs.obs_scene_from_source(scene_source)

            audio_filter_recursive(scene, true)
            obs.obs_source_release(scene_source)
        end
	end
end

function hotkey_callback(pressed)
	if not pressed then
		return
	end

    livestream_cutoff()
end

function script_description()
	return "直播延迟脚本\n\n - 1080P60延迟5秒大约需要2.5G内存，请谨慎使用。\n - 请使用工作室模式并关闭转场动画右侧的“复制场景”。\n - 不要删除LIVESTREAM_DELAY滤镜。"
end

function script_properties()
	local props = obs.obs_properties_create()
    obs.obs_properties_add_bool(props, PROP_ENABLED, '启用')
    local p_delay = obs.obs_properties_add_int_slider(props, PROP_DELAY, '延迟', 0, 10000, 1)
    obs.obs_property_int_set_suffix(p_delay, 'ms')
    local p_video = obs.obs_properties_add_list(props, PROP_SCENE, "延迟场景", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)

	local sources = obs.obs_frontend_get_scenes()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			local name = obs.obs_source_get_name(source)
			obs.obs_property_list_add_string(p_output, name, name)
			obs.obs_property_list_add_string(p_video, name, name)
		end
	end
	obs.source_list_release(sources)

	return props
end

function script_update(settings)
    local sources = obs.obs_frontend_get_scenes()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			remove_filter(source)
		end
	end
	obs.source_list_release(sources)

    sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			remove_filter(source)
		end
	end
	obs.source_list_release(sources)

	enabled = obs.obs_data_get_bool(settings, PROP_ENABLED)
	delay_ms = obs.obs_data_get_int(settings, PROP_DELAY)
	scene_name = obs.obs_data_get_string(settings, PROP_SCENE)

    livestream_cutoff()
end

function script_defaults(settings)
	obs.obs_data_set_default_bool(settings, PROP_ENABLED, false)
	obs.obs_data_set_default_int(settings, PROP_DELAY, 5000)
end

function script_save(settings)
	local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
	obs.obs_data_set_array(settings, PROP_HOTKEY, hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end

function script_load(settings)
    local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_create", source_create)

	hotkey_id = obs.obs_hotkey_register_frontend(PROP_HOTKEY, "这段切掉！", hotkey_callback)
	local hotkey_save_array = obs.obs_data_get_array(settings, PROP_HOTKEY)
	obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end

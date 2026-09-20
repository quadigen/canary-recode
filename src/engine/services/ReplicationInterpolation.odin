#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"

replication_render_interpolated :: proc(service: ^ReplicatorService, delta_time: f32) {
	if service.mode != .Client {return}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	for &entity in service.entities {
		if entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") ||
		   len(entity.samples) == 0 {continue}
		if players != nil && players.local_player != nil {
			if entity.object.parent != nil &&
			   classes.Is_A(entity.object.parent, "CharacterModel") {
				model := cast(^classes.CharacterModel)entity.object.parent
				if model.owner_user_id == players.local_player.user_id {continue}
			} else if entity.owner_id == players.local_player.user_id {continue}
		}
		entity.sample_age += delta_time
		latest := entity.samples[len(entity.samples) - 1]
		target :=
			f64(latest.tick) -
			f64(service.interpolation_delay_ticks) +
			f64(entity.sample_age) * f64(service.snapshot_rate)
		frame := entity.samples[0].frame
		if target >= f64(latest.tick) {
			frame = latest.frame
		} else {
			for index := 1; index < len(entity.samples); index += 1 {
				right := entity.samples[index]
				if target > f64(right.tick) {continue}
				left := entity.samples[index - 1]
				span := f64(right.tick - left.tick)
				if span > 0 {
					alpha := f32(clamp((target - f64(left.tick)) / span, 0, 1))
					frame = datatypes.CFrame_Lerp(left.frame, right.frame, alpha)
				}
				break
			}
		}
		part := cast(^classes.Part)entity.object
		part.cframe = frame
		part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
	}
}

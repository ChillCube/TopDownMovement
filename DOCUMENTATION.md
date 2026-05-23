# TopDownMovement API Reference
Generated: 2026-05-23

A godot addon used to create top down movement. Can be used for both player characters and NPCs

## Class: TopDownMovement
**Inherits:** [Node](https://docs.godotengine.org/en/stable/classes/class_node.html)


### ⚙️ Inspector Variables (Exported)
| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| **speed** | `float` | `500` | Maximum movement speed in pixels/sec |
| **acceleration** | `float` | `0.2` | Ramp-up rate (1 = instant, 0 = never accelerates) |
| **deceleration** | `float` | `0.2` | Ramp-down rate (1 = instant stop) |
| **enable_dashing** | `bool` | `true` | Allow the dash mechanic |
| **dash_speed** | `float` | `3.0` | Speed multiplier during a dash |
| **dash_time** | `float` | `0.2` | Duration in seconds of each dash |
| **dash_falloff** | `float` | `0.3` | How quickly dash velocity decays after the timer ends |
| **dash_timeout** | `float` | `0.5` | Cooldown in seconds between dashes |
| **dashes** | `int` | `1` | Number of dashes available before the timeout resets the counter |
| **enable_knockback** | `bool` | `true` | Allow knockback to be applied via request_knockback() |
| **knockback_speed** | `float` | `3.0` | Speed multiplier for knockback impulse |
| **knockback_time** | `float` | `0.3` | Duration in seconds the knockback force is applied |
| **knockback_falloff** | `float` | `0.3` | How quickly knockback velocity decays after the timer ends |
| **remote_lerp_speed** | `float` | `15.0` | Lerp speed used to smooth remote player positions on non-authority clients |

### 🛠️ Methods
| Method | Arguments | Returns | Description |
| :--- | :--- | :--- | :--- |
| **request_movement()** | `direction: Vector2` | `void` |  Public API: submit a movement direction; routes to authority via RPC in multiplayer |
| **request_dash()** | `direction: Vector2` | `void` |  Public API: trigger a dash in the given direction; routes to authority via RPC in multiplayer |
| **request_knockback()** | `direction: Vector2`<br>`strength: float` | `void` |  Public API: apply a knockback impulse; routes to authority via RPC in multiplayer |

---


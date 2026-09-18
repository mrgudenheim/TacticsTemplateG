extends Node3D
## Shared base for every full-screen NDC-quad overlay in the host — the four the event-script
## VM raises ({76} Dark Screen, {3E} Color Screen, {7D} Show Graphic, {91} Show Map Title)
## and, since ADR-0172, [FormationScreenIn]. Each draws one
## (or two) fullscreen quads whose vertex shader rewrites the corners straight to NDC
## (`POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0)`). Because that override moves the
## corners out of the mesh's local AABB, EVERY such quad must carry an oversized
## `custom_aabb` or Godot's frustum culler silently drops it — an invisible overlay,
## and an easy-to-miss footgun that was copy-pasted across all four effects. This base
## owns that one identical, fiddly recipe so a subclass builds a cull-proof overlay
## quad in a single call. Timing, shaders, blend modes and barrier semantics stay in
## the subclass — those genuinely differ per effect and are NOT abstracted here.
##
## [b]It lives in `platform`, and it has now LANDED at `platform`'s address
## (ADR-0172, #1293 group 4).[/b] What this class knows is a GODOT fact, not a game one: an
## NDC-rewritten quad falls outside its own AABB and the frustum culler drops it. ADR-0147 set
## the precedent for where such a fact belongs when it named `pixel_aspect` and `psx_dither`
## `platform`'s — *"a fact six buckets `#include` cannot live inside the first system to
## extract"*. It sat in `Cutscene` only because the VM happened to be its first caller, and
## Cutscene's own charter is that it *"owns no mechanism of its own"*; hosting a base class
## other systems extend is a mechanism. `FormationScreenIn` extending it from `UI` is what
## made that visible.
##
## [b]ADR-0172 BOOKED it `platform` and parked it in `src/core/`, which is a bucket with two
## addresses, and the second address is what broke the stranger rig.[/b] `extends
## ScreenOverlayQuad` is line 1 of `addons/exmateria_ui/formation/FormationScreenIn.gd`: not a
## reference that could be handed in or routed through a port, but the BASE CLASS, so that
## addon could not parse in a project that did not also ship `src/`. Landing the file here
## pays that with no seam at all — `exmateria_platform` is `tier="port"`, one of the two
## `_walk_roots.PORTABLE_TIERS`, so an addon reaching it is FREE under ADR-0202 dec. 2 and the
## reach earns no burn-down row. The alternative — re-authoring the recipe inside the UI addon
## — is the copy-paste this base was created to end (four effects had it, four ways).
##
## [b]It declares NO `class_name`.[/b] `ExMateriaPlatform` is this addon's only global name
## (ADR-0212 dec. 1), so the class is published as `ExMateriaPlatform.ScreenOverlayQuad` and
## reached by that spelling — including in `extends`, which takes a façade constant:
## `extends ExMateriaPlatform.ScreenOverlayQuad` parses and inherits normally, MEASURED in a
## throwaway project against a bare-`class_name` control before any call site was rewritten.
## A consumer that wants the short spelling aliases it back (ADR-0211 dec. 4).
##
## [b]The CONTEXT.md term did NOT move with it.[/b] **Scenario screen overlay** still names the
## four whose *lifetime is the VM's* — every one is a VM child, so freeing the VM frees the
## family. `FormationScreenIn` is not one: it belongs to a screen, and it frees itself the
## vsync its ramp lands. One mechanism, two families; the class is named for the mechanism.
##
## Depth (ADR-0009): full-screen overlays deliberately opt out of the CUSTOM0 ordering
## table via `depth_test_disabled` + `render_priority` in their shaders (that exemption
## is why these meshes don't bake a CUSTOM0 centroid like every other 3D mesh). Since
## `render_priority` is a per-effect concern, it stays on the material the caller passes
## in — this base only owns the mesh + cull plumbing.

## Oversized local AABB that keeps a screen-space mesh off frustum cull. The vertices
## are rewritten to screen space in vertex() (NDC corners for the quad overlays,
## billboarded streaks for ScenarioWeather), so the mesh's real bounds are meaningless;
## this box is large enough to always intersect the frustum. Shared with ScenarioWeather
## (its MultiMesh billboards reference this same constant) so the value lives in one place.
const CULL_AABB := AABB(Vector3(-4096, -4096, -4096), Vector3(8192, 8192, 8192))


## Build one full-screen overlay quad and parent it under this node: a 2x2 QuadMesh
## (the shader ignores the size and remaps corners to NDC), `material_override = mat`,
## shadows off, and the cull-proof AABB. Returns the MeshInstance3D so the caller can
## toggle its `.visible` per pass (e.g. Color Screen hides the quad at pure black, and
## the dual-pass effects build one text + one shadow quad). `mat` is a ShaderMaterial
## (not any Material): the ADR-0009 depth opt-out relies on the shader's
## `depth_test_disabled` + `render_priority`, which a plain material wouldn't carry.
func _make_overlay_quad(quad_name: String, mat: ShaderMaterial) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)  # any size; vertex() remaps corners to NDC
	var mmi := MeshInstance3D.new()
	mmi.name = quad_name
	mmi.mesh = quad
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = CULL_AABB
	add_child(mmi)
	return mmi

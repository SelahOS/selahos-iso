#!/usr/bin/env python3
"""Run the installed Plymouth script interpreter with mock graphics, without plymouthd.

ABI references: upstream script.h, script-parse.h, script-execute.h,
script-lib-math.h and script-lib-string.h. This is a developer test against the
installed plugin, not a supported runtime dependency. Does not touch VT/DRM/PAM.
"""
import ctypes as C
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
lib = C.CDLL("/usr/lib/plymouth/script.so")

class State(C.Structure):
    _fields_=[("user_data", C.c_void_p), ("global_obj", C.c_void_p),
              ("local_obj", C.c_void_p), ("this_obj", C.c_void_p)]
class Result(C.Structure):
    _fields_=[("type", C.c_int), ("object", C.c_void_p)]

lib.script_state_new.argtypes=[C.c_void_p]
lib.script_state_new.restype=C.POINTER(State)
lib.script_parse_string.argtypes=[C.c_char_p,C.c_char_p]
lib.script_parse_string.restype=C.c_void_p
lib.script_execute.argtypes=[C.POINTER(State),C.c_void_p]
lib.script_execute.restype=Result
lib.script_obj_hash_get_number.argtypes=[C.c_void_p,C.c_char_p]
lib.script_obj_hash_get_number.restype=C.c_double
for name in ("script_lib_math_setup","script_lib_string_setup"):
    fn=getattr(lib,name); fn.argtypes=[C.POINTER(State)]; fn.restype=C.c_void_p

MOCK = r"""
mock_width=1280; mock_height=720; setter_calls=0;
Window.GetWidth=fun(){ return global.mock_width; };
Window.GetHeight=fun(){ return global.mock_height; };
Window.GetX=fun(){ return 0; };
Window.GetY=fun(){ return 0; };
Window.SetBackgroundTopColor=fun(r,g,b){};
Window.SetBackgroundBottomColor=fun(r,g,b){};
fun make_image(w,h) {
    local.img;
    img.width=w; img.height=h;
    img.GetWidth=fun(){ return this.width; };
    img.GetHeight=fun(){ return this.height; };
    img.Scale=fun(w,h){ return make_image(w,h); };
    return img;
}
Image=fun(name){ return make_image(160,160); };
Image.Text=fun(text,r,g,b){
    local.img=make_image(300,20);
    img.text=text;
    return img;
};
Sprite=fun(image) {
    local.sprite;
    sprite.image=image; sprite.opacity=1;
    sprite.SetImage=fun(image){ this.image=image; global.setter_calls++; };
    sprite.SetPosition=fun(x,y,z){ this.x=x; this.y=y; this.z=z; global.setter_calls++; };
    sprite.SetZ=fun(z){ this.z=z; global.setter_calls++; };
    sprite.SetOpacity=fun(value){ this.opacity=value; global.setter_calls++; };
    return sprite;
};
Plymouth.SetRefreshFunction=fun(f){ global.callbacks.refresh=f; };
Plymouth.SetDisplayNormalFunction=fun(f){ global.callbacks.normal=f; };
Plymouth.SetDisplayPasswordFunction=fun(f){ global.callbacks.password=f; };
Plymouth.SetDisplayQuestionFunction=fun(f){ global.callbacks.question=f; };
Plymouth.SetDisplayMessageFunction=fun(f){ global.callbacks.message=f; };
Plymouth.SetHideMessageFunction=fun(f){ global.callbacks.hide_message=f; };
Plymouth.SetBootProgressFunction=fun(f){ global.callbacks.progress=f; };
Plymouth.SetQuitFunction=fun(f){ global.callbacks.quit=f; };
"""
CHECKS = r"""
callbacks.normal();
test_initial = settled == !motion_enabled;
for (j=0; j<20; j++) callbacks.refresh();
test_reflect = !motion_enabled || (point.opacity > 0 && logo.opacity == 0);
for (j=0; j<200; j++) callbacks.refresh();
test_settled = settled && logo.opacity == 1 && rings[0].sprite.opacity == 0;
before=setter_calls;
for (j=0; j<500; j++) callbacks.refresh();
test_idle = setter_calls == before;
callbacks.progress(15,0.5);
test_slow = message_text == "Preparing your workspace...";
callbacks.message("Disk check");
callbacks.hide_message("unrelated");
test_message = message_sprite.opacity == 1;
callbacks.hide_message("Disk check");
test_hidden = message_sprite.opacity == 0;
callbacks.password("Unlock disk",1000);
test_password = mode == "password" && logo.opacity == 0 && answer_sprite.image.text == "********************************+";
callbacks.password("Unlock disk",0);
test_backspace = answer_sprite.image.text == "";
callbacks.question("Continue?", "yes");
test_question = mode == "question" && answer_sprite.image.text == "yes";
callbacks.normal();
test_normal = mode == "normal" && prompt_sprite.opacity == 0 && logo.opacity == 1;
mock_width=200; mock_height=480;
callbacks.refresh();
callbacks.password("Long prompt",3);
test_small = prompt_sprite.image.width <= 152 && answer_sprite.image.width <= 152;
callbacks.normal();
callbacks.quit();
test_quit = settled && logo.opacity == 1;
"""
# Keep ops/state/library objects alive to the end: script functions refer to ASTs.
keepalive=[]
for name in ("selah-experience","selah-experience-static"):
    state=lib.script_state_new(None)
    keepalive.extend([state,lib.script_lib_math_setup(state),lib.script_lib_string_setup(state)])
    source=MOCK+(ROOT/f"boot/generated/{name}.script").read_text()+CHECKS
    op=lib.script_parse_string(source.encode(),name.encode())
    assert op, f"Parse failed: {name}"
    keepalive.append(op)
    result=lib.script_execute(state,op)
    assert result.type == 0, (name,result.type)
    for check in ("initial","reflect","settled","idle","slow","message","hidden","password",
                  "backspace","question","normal","small","quit"):
        assert lib.script_obj_hash_get_number(state.contents.global_obj,("test_"+check).encode()) == 1, (name,check)
    print(f"PASS: {name}: native interpreter, bounded animation, prompts, messages, resize and quit.")

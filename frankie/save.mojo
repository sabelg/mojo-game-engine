"""Versioned campaign progress with validated parsing and atomic replacement."""
from std.ffi import external_call

struct Progress(ImplicitlyCopyable, Movable):
    var unlocked: Int
    var best_score: Int
    var completions: Int
    var muted: Bool

    def __init__(out self):
        self.unlocked = 0
        self.best_score = 0
        self.completions = 0
        self.muted = False

    def encode(self) -> String:
        return "YO_FRANKIE_VK_1\n"+String(self.unlocked)+"\n"+String(self.best_score)+"\n"+String(self.completions)+"\n"+String(Int(self.muted))+"\n"

    @staticmethod
    def decode(source: String) raises -> Self:
        var lines = source.split("\n")
        if len(lines) != 6 or String(lines[0]) != "YO_FRANKIE_VK_1": raise Error("Invalid Yo Frankie save")
        var result = Self()
        result.unlocked = Int(String(lines[1]))
        result.best_score = Int(String(lines[2]))
        result.completions = Int(String(lines[3]))
        var mute = Int(String(lines[4]))
        if result.unlocked < 0 or result.unlocked > 127 or result.best_score < 0 or result.completions < 0 or mute < 0 or mute > 1:
            raise Error("Invalid saved progress values")
        result.muted = mute == 1
        return result

    @staticmethod
    def load(var path: String) raises -> Self:
        if external_call["access",Int32](path.as_c_string_span(),Int32(0)) != 0:
            var err = external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
            if err[] == 2: return Self()
            raise Error("Cannot access save file")
        with open(path,"r") as file: return Self.decode(file.read())

    def save(self, var path: String) raises:
        var temporary = path+".tmp"
        with open(temporary,"w") as file: file.write(self.encode())
        if external_call["rename",Int32](temporary.as_c_string_span(),path.as_c_string_span()) != 0:
            _ = external_call["remove",Int32](temporary.as_c_string_span())
            raise Error("Cannot replace save file")

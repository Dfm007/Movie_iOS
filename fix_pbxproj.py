import pathlib
p = pathlib.Path(r"C:\Users\DUAN\Desktop\iosmovie\iosmovie.xcodeproj\project.pbxproj")
s = p.read_text(encoding="utf-8")
s = s.replace("/* End PBXBuildFile section */", "\t\tB1000000011 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000000011 /* AppDelegate.swift */; };\n/* End PBXBuildFile section */")
s = s.replace("/* End PBXFileReference section */", "\t\tA1000000011 /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = \"<group>\"; };\n/* End PBXFileReference section */")
s = s.replace("AA0000000001 /* iosmovieApp.swift */,", "AA0000000001 /* iosmovieApp.swift */,\n\t\t\t\tA1000000011 /* AppDelegate.swift */,")
s = s.replace("BB0000000001 /* iosmovieApp.swift in Sources */,", "BB0000000001 /* iosmovieApp.swift in Sources */,\n\t\t\t\tB1000000011 /* AppDelegate.swift in Sources */,")
p.write_text(s, encoding="utf-8")
print("pbxproj updated")

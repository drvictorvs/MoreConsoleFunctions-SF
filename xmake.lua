-- MoreConsoleFunctions_SF: SFSE plugin that adds short console commands and hands them to MoreConsoleFunctions_SF.psc.
-- The transporter that used to live here is its own project now (Transporter-SF).
-- Built on the libxse CommonLibSF plugin template (https://github.com/libxse/commonlibsf-template).

-- CommonLibSF is expected next to this project, in ../commonlibsf, shared by the plugin projects
-- (see README: "Build the plugin"). OSF's fork
-- (github.com/ozooma10/commonlibsf) at the same commit as Transporter-SF, so both plugins build
-- against the same game structures.
includes("../commonlibsf")

set_project("MoreConsoleFunctions-SF")
set_version("0.8.0")
set_license("GPL-3.0")  -- CommonLibSF's license, with its modding exception
set_languages("c++23")
set_warnings("allextra")

add_rules("mode.debug", "mode.releasedbg")
set_defaultmode("releasedbg")  -- optimized, with a .pdb for crash loggers such as Trainwreck
add_rules("plugin.vsxmake.autoupdate")

target("MoreConsoleFunctions_SF")
    add_rules("commonlibsf.plugin", {
        name = "MoreConsoleFunctions_SF",
        author = "Victor",
        description = "Short console commands that forward to MoreConsoleFunctions_SF.psc"
    })

    add_files("src/**.cpp")
    add_headerfiles("src/**.h")
    add_includedirs("src")
    set_pcxxheader("src/pch.h")

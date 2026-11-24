allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    // image_picker_android's release lintVitalAnalyzeRelease currently crashes
    // inside Android Lint's CommentDetector on the pinned AGP toolchain.
    // Keep the app's own lint and all Flutter/Dart tests enabled; skip only
    // this third-party dependency's broken release-only lint task.
    if (project.name == "image_picker_android") {
        tasks.configureEach {
            if (name == "lintVitalAnalyzeRelease") {
                enabled = false
            }
        }
    }
}

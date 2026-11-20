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

// Align every Android library module with the app compile SDK.
// Apply after each plugin project has been evaluated because some Flutter
// plugins overwrite their compileSdk during their own Gradle configuration.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.compileSdk = 37
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

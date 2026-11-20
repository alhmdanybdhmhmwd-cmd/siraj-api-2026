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

// Align Android library modules after all project build scripts have run.
// A project-level afterEvaluate callback is too late here because app evaluation
// can eagerly evaluate plugin projects through evaluationDependsOn(":app").
gradle.projectsEvaluated {
    subprojects.forEach { project ->
        project.extensions
            .findByType<com.android.build.api.dsl.LibraryExtension>()
            ?.compileSdk = 37
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

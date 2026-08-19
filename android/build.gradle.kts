allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// -------------------------------------------------------------
// 全サブプロジェクト (onnxruntime 等) の compileSdk を安全に 36 へ強行引き上げ
// -------------------------------------------------------------
subprojects {
    fun applyCompileSdkOverride() {
        project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileSdkVersion(36)
        }
    }

    if (project.state.executed) {
        applyCompileSdkOverride()
    } else {
        project.afterEvaluate {
            applyCompileSdkOverride()
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
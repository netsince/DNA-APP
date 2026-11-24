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
    afterEvaluate {
        // AGP 9：给**插件子项目**也钉 compileSdk 36。
        // 起因：flutter_plugin_android_lifecycle 要求依赖方 compileSdk ≥ 36，而
        // 若干插件（file_picker 等）默认仍是 34 → checkDebugAarMetadata 会失败。
        // AGP 9 的 CommonExtension 既不是泛型也没有 compileSdk，要按具体扩展类型分派。
        when (val androidExt = extensions.findByName("android")) {
            is com.android.build.api.dsl.ApplicationExtension -> androidExt.compileSdk = 36
            is com.android.build.api.dsl.LibraryExtension -> androidExt.compileSdk = 36
            else -> {}
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

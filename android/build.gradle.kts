import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            if (android?.namespace == null) {
                android?.namespace = "dev.sagarm.wire.${name.replace("-", "_")}"
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val useJvm8 = name in setOf("receive_sharing_intent", "flutter_webrtc", "desktop_drop", "mobile_scanner")
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(if (useJvm8) JvmTarget.JVM_1_8 else JvmTarget.JVM_17)
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        val target = if (useJvm8) JavaVersion.VERSION_1_8 else JavaVersion.VERSION_17
        sourceCompatibility = target.toString()
        targetCompatibility = target.toString()
    }

}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

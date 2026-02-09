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
    if (name == "qr_code_scanner") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                namespace = "com.example.wire.qr_code_scanner"
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val useJvm8 = name in setOf("receive_sharing_intent", "flutter_webrtc", "desktop_drop")
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

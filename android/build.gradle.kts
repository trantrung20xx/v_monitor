// Mọi module Android tải plugin/thư viện từ kho Google và Maven Central.
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Đưa output Gradle về thư mục build chung ở gốc để Flutter tool tìm và dọn nhất quán.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Mỗi module có thư mục con riêng, tránh trùng artifact giữa app và plugin.
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // Đánh giá module app trước để plugin kế thừa được cấu hình Android/Flutter cần thiết.
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    // `gradle clean` chỉ xóa output build, không đụng source hoặc cấu hình.
    delete(rootProject.layout.buildDirectory)
}

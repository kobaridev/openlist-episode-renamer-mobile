pluginManagement { repositories { if (File("/home/hatch/workspace/local-maven").exists()) maven { url = uri("/home/hatch/workspace/local-maven") }; google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { if (File("/home/hatch/workspace/local-maven").exists()) maven { url = uri("/home/hatch/workspace/local-maven") }; google(); mavenCentral() } }
rootProject.name = "OpenListRenamer"
include(":app")

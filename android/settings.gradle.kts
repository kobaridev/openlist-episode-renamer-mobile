val localMaven = File("/home/hatch/workspace/local-maven")
pluginManagement { repositories { if (localMaven.exists()) maven { url = uri(localMaven) }; google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { if (localMaven.exists()) maven { url = uri(localMaven) }; google(); mavenCentral() } }
rootProject.name = "OpenListRenamer"
include(":app")

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinCalendarCore",
    products: [
        .library(name: "FinCalendarCore", targets: ["FinCalendarCore"])
    ],
    targets: [
        .target(name: "FinCalendarCore"),
        .testTarget(name: "FinCalendarCoreTests", dependencies: ["FinCalendarCore"])
    ]
)

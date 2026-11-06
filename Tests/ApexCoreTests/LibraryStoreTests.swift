import XCTest
@testable import ApexCore

final class LibraryStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        // Standardized so /var symlink resolution matches URLs produced by LibraryStore.
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryStoreTests_\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Configuration & Scanning

    @MainActor
    func testConfigureCreatesLibraryStructure() throws {
        let store = LibraryStore(workdir: tempDirectory)
        XCTAssertEqual(store.commands, [])
        XCTAssertEqual(store.notes, [])
        XCTAssertEqual(store.workdirURL, tempDirectory.standardizedFileURL)
        for sub in ["commands", "notes"] {
            let dir = tempDirectory.appendingPathComponent(sub, isDirectory: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "configure should create \(sub)/")
        }
    }

    @MainActor
    func testScanPicksUpExternallyCreatedFilesAndGroups() throws {
        let fm = FileManager.default
        let commands = tempDirectory.appendingPathComponent("commands", isDirectory: true)
        try fm.createDirectory(at: commands.appendingPathComponent("Docker"), withIntermediateDirectories: true)
        try Data("docker ps".utf8).write(to: commands.appendingPathComponent("列出容器.sh"))
        try Data("uptime".utf8).write(to: commands.appendingPathComponent("负载.sh"))
        try Data("ignored".utf8).write(to: commands.appendingPathComponent("readme.txt"))
        try Data("hidden".utf8).write(to: commands.appendingPathComponent(".DS_Store"))

        let store = LibraryStore(workdir: tempDirectory)
        XCTAssertEqual(store.commands.map(\.title), ["负载", "列出容器"])
        XCTAssertEqual(store.commands[0].group, nil)
        XCTAssertEqual(store.commands[1].group, "Docker")
        XCTAssertEqual(store.commandGroups, ["Docker"])
        XCTAssertEqual(store.notes, [])
    }

    // MARK: - File Lifecycle

    @MainActor
    func testCreateReadWriteDeleteLifecycle() throws {
        let store = LibraryStore(workdir: tempDirectory)
        let file = try store.createFile(kind: .command, title: "重启 nginx", group: "运维", content: "systemctl restart nginx")
        XCTAssertEqual(file.title, "重启 nginx")
        XCTAssertEqual(file.group, "运维")
        XCTAssertEqual(store.commands.count, 1)
        XCTAssertEqual(store.commandGroups, ["运维"])
        XCTAssertEqual(try store.read(file), "systemctl restart nginx")

        try store.write(file, content: "systemctl restart nginx\nsleep 1")
        XCTAssertEqual(try store.read(file), "systemctl restart nginx\nsleep 1")

        try store.delete(file)
        XCTAssertEqual(store.commands, [])
        XCTAssertThrowsError(try store.read(file))
    }

    @MainActor
    func testCreateFileDeduplicatesTitles() throws {
        let store = LibraryStore(workdir: tempDirectory)
        let first = try store.createFile(kind: .note, title: "排查手册", content: "# a")
        let second = try store.createFile(kind: .note, title: "排查手册", content: "# b")
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(second.title, "排查手册 2")
    }

    @MainActor
    func testRenameUpdatesTitleAndDiskFile() throws {
        let store = LibraryStore(workdir: tempDirectory)
        let file = try store.createFile(kind: .command, title: "旧名字", content: "ls")
        let renamed = try store.rename(file, toTitle: "新名字/带斜杠")
        XCTAssertEqual(renamed.title, "新名字-带斜杠")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.url.path))
        XCTAssertEqual(try store.read(renamed), "ls")
    }

    @MainActor
    func testRenameRejectsCollision() throws {
        let store = LibraryStore(workdir: tempDirectory)
        _ = try store.createFile(kind: .command, title: "A", content: "a")
        let b = try store.createFile(kind: .command, title: "B", content: "b")
        XCTAssertThrowsError(try store.rename(b, toTitle: "A")) { error in
            XCTAssertEqual(error as? LibraryStoreError, .targetExists(tempDirectory.appendingPathComponent("commands/A.sh")))
        }
    }

    @MainActor
    func testMoveBetweenGroupsAndTopLevel() throws {
        let store = LibraryStore(workdir: tempDirectory)
        let file = try store.createFile(kind: .note, title: "网络笔记", group: "基础", content: "# net")

        let moved = try store.move(file, toGroup: "进阶")
        XCTAssertEqual(moved.group, "进阶")
        XCTAssertTrue(moved.url.path.hasSuffix("notes/进阶/网络笔记.md"))

        let topLevel = try store.move(moved, toGroup: nil)
        XCTAssertEqual(topLevel.group, nil)
        XCTAssertTrue(topLevel.url.path.hasSuffix("notes/网络笔记.md"))
        XCTAssertEqual(store.noteGroups.sorted(), ["基础", "进阶"].sorted())
    }

    // MARK: - Group Management

    @MainActor
    func testGroupRenameMovesContainedFiles() throws {
        let store = LibraryStore(workdir: tempDirectory)
        _ = try store.createFile(kind: .command, title: "清理镜像", group: "Docker", content: "docker image prune")

        let renamed = try store.renameGroup("Docker", to: "容器", kind: .command)
        XCTAssertEqual(renamed, "容器")
        XCTAssertEqual(store.commandGroups, ["容器"])
        XCTAssertEqual(store.commands.first?.group, "容器")
        XCTAssertTrue(store.commands.first?.url.path.hasSuffix("commands/容器/清理镜像.sh") ?? false)
    }

    @MainActor
    func testDeleteGroupRequiresConfirmationWhenNonEmpty() throws {
        let store = LibraryStore(workdir: tempDirectory)
        _ = try store.createFile(kind: .note, title: "临时", group: "草稿", content: "x")

        XCTAssertThrowsError(try store.deleteGroup("草稿", kind: .note)) { error in
            XCTAssertEqual(error as? LibraryStoreError, .groupNotEmpty("草稿", 1))
        }
        XCTAssertEqual(store.notes.count, 1)

        let removed = try store.deleteGroup("草稿", kind: .note, includingFiles: true)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.notes, [])
        XCTAssertEqual(store.noteGroups, [])
    }

    // MARK: - Naming

    func testSanitizedTitleStripsPathSeparatorsAndLeadingDots() {
        XCTAssertEqual(LibraryStore.sanitizedTitle("a/b:c\\d"), "a-b-c-d")
        XCTAssertEqual(LibraryStore.sanitizedTitle("  .隐藏  "), "隐藏")
        XCTAssertEqual(LibraryStore.sanitizedTitle("   "), "")
    }

    // MARK: - Snippet Migration

    @MainActor
    func testMigrateSnippetsCreatesCommandFilesOnce() throws {
        let store = LibraryStore(workdir: tempDirectory)
        let snippets = [
            Snippet(title: "磁盘空间", command: "df -h", category: "系统"),
            Snippet(title: "查进程", command: "ps aux | grep {{service}}", category: "General"),
            Snippet(title: "空命令", command: "  ", category: "系统")
        ]
        let migrated = try store.migrateSnippets(from: snippets)
        XCTAssertEqual(migrated, 2)
        XCTAssertEqual(store.commands.count, 2)

        let grouped = store.commands.first(where: { $0.title == "磁盘空间" })
        XCTAssertEqual(grouped?.group, "系统")
        XCTAssertEqual(try store.read(grouped!), "df -h")

        let topLevel = store.commands.first(where: { $0.title == "查进程" })
        XCTAssertEqual(topLevel?.group, nil)

        // Second run is a no-op: commands already exist.
        XCTAssertEqual(try store.migrateSnippets(from: snippets), 0)
        XCTAssertEqual(store.commands.count, 2)
    }
}

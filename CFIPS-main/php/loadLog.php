<?php
    $logFile = '../going.txt';
    $linesToShow = 50;

    if(file_exists($logFile)){
        $file = new SplFileObject($logFile, 'r');
        $file->seek(PHP_INT_MAX);
        $totalLines = $file->key();

        $linesToSkip = max(0, $totalLines - $linesToShow);
        $file->seek($linesToSkip);

        while (!$file->eof()) {
            echo nl2br($file->fgets());
        }
    } else {
        echo '无法找到日志文件。';
    }
?>

<table>
    <tr>
        <th>扫描任务列表</th>
        <th>-</th>
        <th>扫描结果</th>
    </tr>
    <?php
    $files = glob('../ASN/*.txt');
    $going = file_get_contents('../going.txt');
    preg_match_all('/Scan ASN ((AS\d+)[^\d]*)/', $going, $matches);
    $scanningAsn = end($matches[1]);
    $log = file_get_contents('../going.txt'); // 替换为你的日志文件路径
    foreach ($files as $file) {
        $filename = basename($file, '.txt');
        preg_match('/AS\d+/', $filename, $matches);
        $asn = $matches[0];
        if ($asn == $scanningAsn) {
            $status = '扫描中...';
        } else {
            preg_match("/ASN: ({$asn}[^\d]*)\s+IPs: \d+\s+Valid IPs: (\d+)/", $log, $matches);
            $status = isset($matches[2]) ? $matches[2] : '待扫描';
        }
        echo "<tr><td><a href='https://whois.ipip.net/$asn' target='_blank' style='color: inherit; text-decoration: none;'>$asn</a></td><td></td><td>$status</td></tr>";
    }
    ?>
</table>

<!DOCTYPE html>
<html>
<head>
    <title>CloudFlareIPScan</title>
    <link rel="icon" href="favicon.ico" type="image/x-icon">
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.5.1/jquery.min.js"></script>
    <style>
        #scanLog {
            height: 300px;
            overflow: auto;
            border: 1px solid black;
            padding: 10px;
        }
        #progressBar {
            width: 100%;
            background-color: #f3f3f3;
        }
        #progressBar div {
            height: 30px;
            background-color: #4CAF50;
            text-align: right;
            line-height: 30px;
            color: white;
        }
    </style>
    <script>
        $(document).ready(function(){
            loadStatus();
            loadLog();
            loadServerInfo();
            loadTaskList();
            setInterval(loadStatus, 30000);//扫描任务进度
            setInterval(loadLog, 30000);//扫描日志
            setInterval(loadServerInfo, 5000);//服务器状态
            setInterval(loadTaskList, 60000);//扫描任务列表
        });

        function loadStatus() {
            $.get('loadStatus.php', function(data) {
                var lines = data.split('<br>');
                $('#status').html(lines.slice(0, -2).join('<br>'));
                var progress = lines[lines.length - 2];
                progress = progress.replace('扫描进度：', '').replace('%', '');
                $('#progressBar div').css('width', progress + '%').text(progress + '%');
            });
        }

        function loadLog() {
            $("#scanLog").load('loadLog.php', function() {
                var elem = document.getElementById('scanLog');
                elem.scrollTop = elem.scrollHeight;
            });
        }

        function loadServerInfo() {
            $("#serverInfo").load('loadServerInfo.php');
        }
		
		function loadTaskList() {
            $("#taskList").load('loadTaskList.php');
        }
    </script>
</head>
<body>
    <h1>CloudFlareIPScan</h1>
    <div id="serverInfo"></div>
	<br>
    <div id="status"></div>
	<br>
	扫描日志：
    <div id="scanLog"></div>
	<div id="progressBar"><div></div></div>
	<br>
	<div id="taskList"></div>
</body>
</html>

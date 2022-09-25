Imports System.Data.SqlClient

Module Module1

    Private _server As String = "localhost"
    Private _instance As String = "\"
    Private _catalog As String = "master"
    Private _password As String = ""
    Private _username As String = ""
    Private _useIntegrated As Boolean = True
    Private _delta As Integer = 5 'seconds
    Private _factor As Single = 1 '>1 will increase the delta over time, while <1 will decrease it
    Private _currentTimeSpan As Integer = _delta * _factor
    Private _hoursToRun As Single = 1
    Private _protocol As String = "dbmssocn"
    Private _pooling As Boolean = False
    Private _quiet As Boolean = False
    'BK 01 Nov 2008 -- added support for a query to be sent from the command line.
    Private _queryToExecute As String = "Select @@version"
    Private _weHaveAQuery As Boolean = False
    Private _connectionTimeout As Integer = 15
    Private _iterations As Integer = 10
    Private _doFill As Boolean = False

    'We are going to cheat to get the data written out to a text file.  Since I don't have a good way to capture the ctrl-c, I am going to use a listener and the autoflush setting and assume that the Framework developers were smart enough to deal with a sudden shutdown

    Sub Main(ByVal args() As String)

        If args.GetLength(0) = 0 Or args.GetLength(0) = 1 Then
            Console.WriteLine("You must pass in the SQL Server instance, a valid username and password (or use integrated authentication)")
            Console.WriteLine("-Sserver")
            Console.WriteLine("-ddatabase")
            Console.WriteLine("-USQL Server login")
            Console.WriteLine("-PSQL Server password")
            Console.WriteLine("-Etrusted connection")
            Console.WriteLine("-TDelta between connections(seconds)")
            Console.WriteLine("-FFactor for the connection delta")
            Console.WriteLine("-HTime to Run (hours)")
            Console.WriteLine("-CProtocol(tcp, or np) - If you want LPC, specify it by using a ""."" for the servername")
            'BK 01 Nov 2008 -- added support for a query to be sent from the command line.
            'BK 10 Feb 2009 -- added help text to instruct users to enclose queries in quotes, to accommodate spaces
            Console.WriteLine("-QQuery to execute (results will NOT be displayed; enclose query in quotes)")
            Console.WriteLine("-RFill Dataset with query results")
            Console.WriteLine("-tConnection Timeout (seconds)")
            Console.WriteLine("-q If specified, will launch immediately with no interaction from the user")
            Console.WriteLine("-bNumber of connections in a batch")
            Exit Sub
        Else
            ProcessCommandLineArguments(args)
        End If

        'now that we know we have good inputs, tell the user what we are doing and are going to do 

        'figure out when we started
        Dim ts As New System.DateTime
        ts = Now()
        'figure out when we are going to end
        Dim te As New System.DateTime
        te = ts.AddHours(_hoursToRun)
        Debug.WriteLine(te)

        If (_quiet = False) Then
            Console.WriteLine("All data will be written to the log file specified in the app.config file")
            Console.WriteLine("Data will be collected until approximately " & te.ToString)
            Console.WriteLine("You can manually stop collection by hitting ctrl-c")
            Console.WriteLine("Hit enter to start collecting data...")
            Console.ReadLine()
            'BK 10 Feb 2009 -- added a column heading for query execution time if a query was submitted.
            If _weHaveAQuery Then
                Trace.WriteLine("Login Time,Server,Integrated Authentication,Login (ms),Query (ms),Result")
            Else
                Trace.WriteLine("Login Time,Server,Integrated Authentication,Login (ms),Result")
            End If
        End If


        'We want to do a login loop with the intial delta passed in (in seconds).  Then, modify  that delta by the factor passed in.  This allows us to adjust the delta over time without restarting the application.
        'First, kick the process off with the initial set of logins
        DoLogins()
        Console.WriteLine("The next set of logins will be done at approximately " & Now.AddMilliseconds(_currentTimeSpan * 1000).ToString)

        'now, enter the loop
        Debug.WriteLine(DateTime.Compare(te, Now()))
        'Set the initial delta
        _currentTimeSpan = _delta
        While Not DateTime.Compare(te, Now()) < 0
            Threading.Thread.Sleep(_currentTimeSpan * 1000)
            DoLogins()
            'adjust the delta
            _currentTimeSpan *= _factor
            Console.WriteLine("The next set of logins will be done at approximately " & Now.AddMilliseconds(_currentTimeSpan * 1000).ToString)
        End While


    End Sub

    'BK 06 Nov 2008 Changed this to a Sub since it returns nothing
    Private Sub DoLogins()
        Dim cn As SqlConnection
        Dim strCn As String = ""
        Console.WriteLine(Now().ToString & ":Getting ready to open a batch of connections - " + _iterations.ToString())
        Dim result As String = ""
        'Now, we need to loop through the connection 10 times to get a good average
        For i As Integer = 0 To _iterations - 1
            'BK 06 Nov 2008 Added separate timing tracking for the query
            Dim ts As New System.DateTime
            Dim te As New System.DateTime
            Dim tqs As New System.DateTime
            Dim tqe As New System.DateTime

            If _useIntegrated = False Then
                strCn = "Pooling=False;Password=" & _password & ";User ID=" & _username & ";Initial Catalog=" & _catalog & ";Data Source=" & _server & ";Application Name=ConnectionTracker;Network Library=" & _protocol
            Else
                strCn = "Pooling=False;Integrated Security=SSPI;Initial Catalog=" & _catalog & ";Data Source=" & _server & ";Application Name=ConnectionTracker;Network Library=" & _protocol
            End If

            'based on the hidden switch, turn on pooling
            If _pooling Then
                strCn = strCn.Replace("Pooling=False;", "")
            End If

            strCn += (";Connection Timeout=" + _connectionTimeout.ToString)

            cn = New SqlConnection(strCn)
            Console.WriteLine("Getting ready to open a single connection")
            Try
                ts = Now()
                cn.Open()
                result = "S_OK"
            Catch ex As Exception
                result = ex.Message
                Console.WriteLine(ex.Message)
            Finally
                te = Now()
            End Try
            'BK 06 Nov 2008 Added handling for command-line query
            'only execute the query if the connection attempt was good
            If (result = "S_OK") Then
                If (_weHaveAQuery) Then
                    If (_doFill) Then
                        'in this case, fill a DataSet so that we capture the time required to stream the resultset down
                        'a Dataset is a good choice for this measurement b/c underneath we just cycle through a DataReader
                        Try
                            Dim cmd As New SqlCommand(_queryToExecute, cn)
                            Dim ds As New DataSet
                            Dim da As New SqlDataAdapter
                            da.SelectCommand = cmd
                            tqs = Now
                            da.Fill(ds)
                            result = "S_OK"
                        Catch ex As Exception
                            'command failure
                            result = ex.Message
                            Console.WriteLine(ex.Message)
                        Finally
                            tqe = Now
                        End Try
                    Else
                        Try
                            tqs = Now
                            Dim cmd As New SqlCommand(_queryToExecute, cn)
                            cmd.ExecuteNonQuery()
                            result = "S_OK"
                        Catch ex As Exception
                            'command failure
                            result = ex.Message
                            Console.WriteLine(ex.Message)
                        Finally
                            tqe = Now
                        End Try
                    End If
                End If
            End If

            cn.Close()
            Console.WriteLine("Opening the single connection took " & Math.Round(te.Subtract(ts).TotalMilliseconds, 0) & " milliseconds")
            If (_weHaveAQuery And result = "S_OK" And (_doFill = True)) Then
                Console.WriteLine("Executing the query and filling the dataset took " & Math.Round(tqe.Subtract(tqs).TotalMilliseconds, 0) & " milliseconds")
            ElseIf (_weHaveAQuery And result = "S_OK" And (_doFill = False)) Then
                Console.WriteLine("Executing the query took " & Math.Round(tqe.Subtract(tqs).TotalMilliseconds, 0) & " milliseconds")
            End If

            Trace.Write(ts & "," & _server & "," & _useIntegrated)
            'If result.ToUpper = "S_OK" Then
            Trace.Write("," & Math.Round(te.Subtract(ts).TotalMilliseconds, 0))
            'Else
            '    Trace.Write(",-1")
            'End If
            If (_weHaveAQuery) Then
                Trace.Write("," & Math.Round(tqe.Subtract(tqs).TotalMilliseconds, 0))
            End If
            Trace.WriteLine("," & result)
        Next

    End Sub

    'BK 06 Nov 2008 Changed this to a Sub since it returns nothing
    Private Sub ProcessCommandLineArguments(ByVal inputArgs() As String)
        Trace.WriteLine("ConnectionTracker was started with these arguments:")
        Dim args() As String = inputArgs
        For i As Integer = 0 To args.GetLength(0) - 1
            'based on the way we spec the incoming args, we can just read the first character to figure out which switch we are processing
            'then, we can read everything >1 for the WriteLine
            Trace.WriteLine("Evaluating argument: " & args(i).Substring(1, 1))
            Trace.WriteLine("Argument value is: " & args(i).Substring(2))
            Select Case args(i).Substring(1, 1)
                Case "S"
                    _server = args(i).Substring(2)

                Case "d"
                    _catalog = args(i).Substring(2)
                Case "U"
                    _username = args(i).Substring(2)
                    _useIntegrated = False
                Case "P"
                    _password = args(i).Substring(2)
                    _useIntegrated = False
                Case "E"
                    _useIntegrated = True
                Case "T"
                    _delta = args(i).Substring(2)
                Case "F"
                    _factor = args(i).Substring(2)
                Case "H"
                    _hoursToRun = args(i).Substring(2)
                Case "C"
                    _protocol = args(i).Substring(2)
                    Select Case _protocol
                        Case "tcp"
                            _protocol = "dbmssocn"
                        Case "np"
                            _protocol = "dbnmpntw"
                    End Select
                Case "Q"
                    If Not args(i).Substring(2) = "" Then _queryToExecute = args(i).Substring(2)
                    _weHaveAQuery = True
                Case "p"
                    _pooling = True
                Case "q"
                    _quiet = True
                Case "t"
                    _connectionTimeout = args(i).Substring(2)
                Case "b"
                    If args(i).Substring(2) <> String.Empty Then
                        _iterations = args(i).Substring(2)
                    End If
                Case "R"
                    _doFill = True
                Case Else
                    Console.WriteLine("Invalid command-line argument passed -" & args(i).Substring(1, 1) & args(i).Substring(2))
                    'BK 10 Feb 2009 -- added another feedback here that queries need to be in quotation marks.
                    If _weHaveAQuery Then
                        Console.WriteLine("(please note that queries need to be enclosed in quotation marks, to account for spaces)")
                    End If

            End Select
        Next
        'we also need to account for a local scenario, where we want lpc
        'TODO:  improve the logic here
        'this change is specifically to accomodate Daas and FQDNs
        If _server.Substring(0, 1) = "." Then
            'If _server.LastIndexOf(".") >= 0 Then
            _protocol = "dbmslpcn"
            Console.WriteLine("WARNING - Changed protocol to LPC because ""."" was specified for server")
            Trace.WriteLine("WARNING - Changed protocol to LPC because ""."" was specified for server")
        End If
    End Sub

End Module


using System.Data;
using Microsoft.Data.SqlClient;
using System.Diagnostics;

namespace ConnectionTrackerEverywhere
{
    internal static class Program
    {
        private static string _server = "localhost";
        private static string _catalog = "master";
        private static string _password = "";
        private static string _username = "";
        private enum authenticationModeOptions
        {
            Integrated=1,
            EntraIDIntegrated=0, //since it's 2024 and Entra+MFA is the norm, make it the new default
            EntraIDInteractive =2,
            SQLAuthentication=4
        }
        private static authenticationModeOptions _authenticationMode;
        private static int _delta = 5; // seconds
        private static double _factor = 1; // >1 will increase the delta over time, while <1 will decrease it
        private static double _currentTimeSpan;
        private static int _hoursToRun = 1;
        private static bool _pooling = false;
        private static bool _quiet = false;
        // BK 01 Nov 2008 -- added support for a query to be sent from the command line.
        private static string _queryToExecute = "Select @@version";
        private static bool _weHaveAQuery = false;
        private static int _connectionTimeout = 15;
        private static bool _doFill = false;
        private static int _iterations = 10;

        static void Main(string[] args)
        {
            //set up a listener so everything gets logged to disk
            TextWriterTraceListener myListener = new TextWriterTraceListener("ConnectionTrackerEverywhere.log", "myListener");
            Trace.Listeners.Add(myListener);
            Trace.AutoFlush = true;

            if (args.GetLength(0) == 0 | args.GetLength(0) == 1)
            {
                Console.WriteLine("You must pass in the SQL Server instance, a valid username and password, use integrated authentication, or use interactive or integrated EntraID authentication");
                Console.WriteLine("-Sserver");
                Console.WriteLine("-ddatabase");
                Console.WriteLine("-USQL Server login");
                Console.WriteLine("-PSQL Server password");
                Console.WriteLine("-Etrusted connection");
                //-i for Entra ID integrated authentiction (aka Azure Active Directory integrated)
                Console.WriteLine("-iEntra authentication");
                //-I for Entra ID interactive authentication to cover MFA (aka Azure Active Directory interactive)
                Console.WriteLine("-IEntra integrated authentication");
                Console.WriteLine("-TDelta between connections(seconds)");
                Console.WriteLine("-FFactor for the connection delta (note: enclose in \"\" if you want to pass in a decimal");
                Console.WriteLine("-HTime to Run (hours)");
                // BK 01 Nov 2008 -- added support for a query to be sent from the command line.
                // BK 10 Feb 2009 -- added help text to instruct users to enclose queries in quotes, to accommodate spaces
                Console.WriteLine("-QQuery to execute (results will NOT be displayed; enclose query in quotes)");
                Console.WriteLine("-RFill Dataset with query results");
                Console.WriteLine("-tConnection Timeout (seconds)");
                Console.WriteLine("-q If specified, will launch immediately with no interaction from the user");
                Console.WriteLine("-bNumber of connections in a batch");
                return;
            }
            else
            {
                ProcessCommandLineArguments(args);
            }

            // now that we know we have good inputs, tell the user what we are doing and are going to do 

            // figure out when we started
            System.DateTime ts = new System.DateTime();
            ts = DateTime.Now;
            // figure out when we are going to end
            System.DateTime te = new System.DateTime();
            te = ts.AddHours(_hoursToRun);
            Debug.WriteLine(te);

            if (!_quiet)
            {
                Console.WriteLine("All data will be written to the log file specified in the app.config file");
                Console.WriteLine("Data will be collected until approximately " + te.ToString());
                Console.WriteLine("Starting delta between batches of " + _iterations.ToString() + " is " + _delta + " seconds");
                Console.WriteLine("Delta factor is " + _factor.ToString());
                Console.WriteLine("Authentication mode = " + _authenticationMode.ToString());
                Console.WriteLine("You can manually stop collection by hitting ctrl-c");
                Console.WriteLine("Hit enter to start collecting data...");
                Console.ReadLine();

                //BK 10 Feb 2009 -- added a column heading for query execution time if a query was submitted
                if (_weHaveAQuery)
                {
                    Trace.WriteLine("Login Time,Server,Authentication Mode,Login (ms),Query (ms),Result");
                }
                else
                {
                    Trace.WriteLine("Login Time,Server,Authentication Mode,Login (ms),Result");
                }
            }

            //We want to do a login loop with the intial delta passed in (in seconds).  Then, modify  that delta by the factor passed in.  This allows us to adjust the delta over time without restarting the application.
            //First, kick the process off with the initial set of logins
            DoLogins();
            Console.WriteLine("The next set of logins will be done at approximately " + DateTime.Now.AddMilliseconds(_currentTimeSpan * 1000).ToString());

            //now, enter the loop
            _currentTimeSpan = _delta * _factor;
            while (DateTime.Compare(te, DateTime.Now) > 0)
            {
                Debug.WriteLine("Haven't exceeded end time - running another batch");

                int _sleepTime = (int) Math.Round(_currentTimeSpan *1000,0);
#if DEBUG
                Debug.WriteLine("_sleepTime = " + _sleepTime.ToString());
#endif
                Thread.Sleep(_sleepTime);  //round to the closest milliseconds for use 

                Debug.WriteLine("Getting ready to DoLogins");
                DoLogins();
                //after the first iteration, increase _delta by _factor
                _currentTimeSpan *= _factor;

                Debug.WriteLine("_currentTimeSpan = " + _currentTimeSpan.ToString());
                Console.WriteLine("The next set of logins will be done at approximately " + DateTime.Now.AddMilliseconds(_currentTimeSpan * 1000).ToString());
            }
        }

        private static void DoLogins()
        {
            //build and define the connection string
            SqlConnection cn;
            string strCn = "";
            switch (_authenticationMode)
            {
                case authenticationModeOptions.Integrated:
                    strCn = "Pooling=False; Integrated Security=SSPI; Initial Catalog=" + _catalog + ";Data Source=" + _server + ";Application Name=ConnectionTrackerEverywhere";
                    break;
                case authenticationModeOptions.EntraIDIntegrated:
                    strCn = "Pooling=False; Authentication=Active Directory Integrated; Initial Catalog=" + _catalog + ";Data Source=" + _server + ";Application Name=ConnectionTrackerEverywhere";
                    break;
                case authenticationModeOptions.EntraIDInteractive:
                    strCn = "Pooling=False; Authentication=Active Directory Interactive; Initial Catalog=" + _catalog + ";Data Source=" + _server + ";Application Name=ConnectionTrackerEverywhere";
                    break;
                case authenticationModeOptions.SQLAuthentication:
                    strCn = "Pooling=False; Password=" + _password + ";User ID=" + _username + " ;Initial Catalog=" + _catalog + ";Data Source=" + _server + ";Application Name=ConnectionTrackerEverywhere";
                    break;
            }

            //based on the hidden switch, turn on pooling
            if (_pooling)
            {
                strCn = strCn.Replace("Pooling=False;", "");
            }

            strCn += ";Connection Timeout=" + _connectionTimeout.ToString();

#if DEBUG
            Console.WriteLine(strCn);
#endif


            Console.WriteLine(DateTime.Now.ToString() + ":Getting ready to open a batch of " + _iterations.ToString() + " connections");
            string result = "";
            //Now, we need to loop through the connection 10 times to get a good average
            for (int i = 0; i < _iterations; i++)
            {

#if DEBUG
                Console.WriteLine("DoLogin iteration: " +i.ToString());
#endif

                //BK 06 Nov 2008 Added separate timing tracking for the query
                DateTime ts = new DateTime();
                DateTime te = new DateTime();
                DateTime tqs = new DateTime();
                DateTime tqe = new DateTime();

                cn = new SqlConnection(strCn);
                Console.WriteLine("Getting ready to open a single connection");

                try
                {
                    ts = DateTime.Now;
                    cn.Open();
                    result = "S_OK";
                }
                catch (Exception ex2)
                {
                    result = ex2.Message;
                    Console.WriteLine(ex2.Message);
                }
                finally
                {
                    te = DateTime.Now;
                }

                //BK 06 Nov 2008 Added handling for command-line query
                //only execute the query if the connection attempt was good
                if (result == "S_OK")
                {
                    if  (_weHaveAQuery)
                    {
                        if (_doFill)
                        {
                            try
                            {
                                SqlCommand cmd = new SqlCommand(_queryToExecute, cn);
                                DataSet ds = new DataSet();
                                SqlDataAdapter da = new SqlDataAdapter();
                                da.SelectCommand = cmd;
                                tqs = DateTime.Now;
                                da.Fill(ds);
                                result = "S_OK";
                            }
                            catch (Exception ex)
                            {
                                //command failure
                                result = ex.Message;
                                Console.WriteLine(ex.Message);
                            }
                            finally
                            {
                                tqe = DateTime.Now;
                            }
                        }
                        else
                        {
                            try
                            {
                                tqs = DateTime.Now;
                                SqlCommand cmd = new SqlCommand(_queryToExecute, cn);
                                cmd.ExecuteNonQuery();
                                result = "S_OK";
                                    }
                            catch (Exception ex4)
                            {
                                //command failure
                                result = ex4.Message; ;
                                Console.WriteLine(ex4.Message);
                            }
                            finally
                            {
                                tqe = DateTime.Now;
                            }
                        }
                    }
                }

                cn.Close();
                Console.WriteLine("Opening the single connection took " + Math.Round(te.Subtract(ts).TotalMilliseconds, 0) + " milliseconds");
                if (_weHaveAQuery && result == "S_OK" && _doFill)
                {
                    Console.WriteLine("Executing the query and filling the dataset took " + Math.Round(tqe.Subtract(tqs).TotalMilliseconds, 0) + " milliseconds");
                }
                else if (_weHaveAQuery && result == "S_OK" && !_doFill)
                {
                    Console.WriteLine("Executing the query took " + Math.Round(tqe.Subtract(tqs).TotalMilliseconds, 0) + " milliseconds");
                }


                Trace.Write(ts + "," + _server + "," + _authenticationMode.ToString());
                Trace.Write("," + Math.Round(te.Subtract(ts).TotalMilliseconds, 0));
                if (_weHaveAQuery)
                {
                    Trace.Write("," + Math.Round(tqe.Subtract(tqs).TotalMilliseconds, 0));
                }
                Trace.WriteLine("," + result);
            }
        }

        private static void ProcessCommandLineArguments(string[] args)
        {
            Trace.WriteLine("ConnectionTracker was started with these arguments:");

            for (int i = 0; i < args.Length; i++)
            {
                //based on the way we spec the incoming args, we can just read the first character to figure out which switch we are processing
                //then, we can read everything >1 for the WriteLine
                Trace.WriteLine("Evaluating argument: " + args[i].Substring(1, 1));
                Trace.WriteLine("Argument value is: " + args[i].Substring(2));
#if DEBUG
                Console.WriteLine(args[i].Substring(1, 1) + " = " + args[i].Substring(2));
#endif
                switch (args[i].Substring(1, 1))
                {
                    case "S":
                        _server = args[i].Substring(2);
                        break;
                    case "d":
                        _catalog = args[i].Substring(2);
                        break;
                    case "U":
                        _username = args[i].Substring(2);
                        _authenticationMode = authenticationModeOptions.SQLAuthentication;
                        break;
                    case "P":
                        _password = args[i].Substring(2);
                        _authenticationMode = authenticationModeOptions.SQLAuthentication;
                        break;
                    case "E":   //the old standby - Integrated authentication
                        _authenticationMode = authenticationModeOptions.Integrated;
                        break;
                    case "i":  //EntraID integrated
                        _authenticationMode = authenticationModeOptions.EntraIDIntegrated;
                        break;
                    case "I":  //EntraID interactive
                        _authenticationMode = authenticationModeOptions.EntraIDInteractive;
                        break;
                    case "T":
                        _delta = int.Parse(args[i].Substring(2));
                        break;
                    case "F":
                        _factor = double.Parse(args[i].Substring(2));
                        break;
                    case "H":
                        _hoursToRun = int.Parse(args[i].Substring(2));
                        break;
                    case "Q":
                        if (args[i].Substring(2) != "")
                        {
                            _queryToExecute = args[i].Substring(2);
                        }
                        _weHaveAQuery = true;
                        break;
                    case "p":
                        _pooling = true;
                        break;
                    case "q":
                        _quiet = true;
                        break;
                    case "t":
                        _connectionTimeout = int.Parse(args[i].Substring(2));
                        break;
                    case "b":
                        if (args[i].Substring(2) != String.Empty)
                        {
                            _iterations = int.Parse(args[i].Substring(2));
                        }
#if DEBUG
                        Console.WriteLine("b = " + _iterations);
#endif
                        break;
                    case "R":
                        _doFill = true;
                        break;
                    default:
                        Console.WriteLine("Invalid command-line argument passed -" + args[i].Substring(1, 1) + args[i].Substring(2));
                        //BK 10 Feb 2009 -- added another feedback here that queries need to be in quotation mark
                        if (_weHaveAQuery)
                        {
                            Console.WriteLine("(please note that queries need to be enclosed in quotation marks, to account for spaces)");
                        }
                        break;
                }
            }
        }
    }
}


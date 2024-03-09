using Azure;
using Kusto.Cloud.Platform.Utils;
using Kusto.Data;
using Kusto.Data.Net.Client;
using Microsoft.Extensions.Configuration;
using System.Text;
using static System.Runtime.InteropServices.JavaScript.JSType;


namespace BasicQuery
{
    class BasicQuery
    {
        //default to current year and the two months previous (to ensure full month data)
        static int startYear = DateTime.Now.Year;
        static int endYear = DateTime.Now.Year;   
        static int startMonth = DateTime.Now.Month-1;
        static int endMonth = DateTime.Now.Month - 2;
        static string targetDatabase = "Samples";
        static string targetClusterURI = "https://help.kusto.windows.net/";
        static string filePath = @"SampleIterativeQuery.kql";
        static bool verboseLogging = false;

        static void Main(string[] args)
        {
            //handle the command line inputs
            var builder = new ConfigurationBuilder();
            builder.AddCommandLine(args);
            var config = builder.Build();

            //loop through and write them out for validation
            foreach (var item in config.GetChildren())
            {
                Console.WriteLine(item.Key + " = " + item.Value);
                switch (item.Key.ToLower()) //case insensitive on the parameters 
                {
                    case "startmonth":
                        startMonth = int.Parse(item.Value);
                        break;
                    case "startyear":
                        startYear = int.Parse(item.Value);
                        break;
                    case "endmonth":
                        endMonth = int.Parse(item.Value);
                        break;
                    case "endyear":
                        endYear = int.Parse(item.Value);
                        break;
                    case "targetdatabase":
                        targetDatabase = item.Value;
                        break;
                    case "targetclusteruri":
                        targetClusterURI = item.Value;
                        break;
                    case "kqlfile":
                        filePath = item.Value;
                        break;
                    case "debug":
                        verboseLogging = bool.Parse(item.Value);
                        break;

                }
            }

            //in order to get the full month, need to turn the inputted strings into DateTimes
            //then back to strings to pass to the KQL
            //don't care about the day of the month, just the month and year
            DateTime firstMonthYearDateTime = new DateTime(startYear, startMonth, 1);
            DateTime lastMonthYearDatetime = new DateTime(endYear, endMonth, 1);

            string clusterUri = targetClusterURI;
            var kcsb = new KustoConnectionStringBuilder(clusterUri)
                .WithAadUserPromptAuthentication();

            string database = targetDatabase;
            string query = File.ReadAllText(filePath, Encoding.UTF8);

            //write out the query for validation
            Console.WriteLine("Baseline query: ");
            Console.WriteLine(query);
            Console.WriteLine();  

            //figure out how many iterations to do
            //need to add one since we are doing inclusively
            int iterations = ((lastMonthYearDatetime.Year - firstMonthYearDateTime.Year) * 12) + lastMonthYearDatetime.Month - firstMonthYearDateTime.Month + 1;

            //set up the output file
            // Write the string array to a new file named "WriteLines.txt"
            using (StreamWriter outputFile = new StreamWriter("output.csv"))
            {
                for (int monthIteration = 0; monthIteration < iterations; monthIteration++) 
                {

                    //we start with the first day of the month, so adding 1 month
                    //don't have to go back since the query is written with < for the termination
                    string startofMonth = firstMonthYearDateTime.AddMonths(monthIteration).FastToString();
                    string endofMonth = firstMonthYearDateTime.AddMonths(monthIteration).AddMonths(1).FastToString();

                    //replace the stubs for $startTime$ and $endTime$ with the actuals
                    string queryLocal = query.Replace("$startTime$", startofMonth);
                    queryLocal = queryLocal.Replace("$endTime$", endofMonth);

                    if (verboseLogging)
                    {
                        //write out the query for validation
                        Console.WriteLine("iteration query: ");
                        Console.WriteLine(queryLocal);
                        Console.WriteLine();
                    }

                    int rowCount = 0;
                    using (var kustoClient = KustoClientFactory.CreateCslQueryProvider(kcsb))
                    {

                        using (var response = kustoClient.ExecuteQuery(database, queryLocal, null))
                        {
                            if (monthIteration==0)
                            {
                                //if on the first iteration, then grab the columns
                                //for subsequent iterations, don't want to output the columns
                                for (int headerColumn = 0; headerColumn < response.FieldCount; headerColumn++)
                                {
                                    outputFile.Write(response.GetName(headerColumn));
                                    if (headerColumn < response.FieldCount - 1)
                                    {
                                        outputFile.Write(",");
                                    }
                                    else
                                    {
                                        outputFile.WriteLine();
                                    }
                                }
                            }

                            //iterate over the fields and write out as a comma-separated result set
                            while (response.Read())
                            {
                                rowCount++;
                                for (int dataColumn = 0; dataColumn < response.FieldCount; dataColumn++)
                                {
                                    outputFile.Write(response.GetValue(dataColumn));
                                    if (dataColumn < response.FieldCount - 1)
                                    {
                                        outputFile.Write(",");
                                    }
                                    else
                                    {
                                        outputFile.WriteLine();
                                    }
                                }
                            }
                        }
                    }

                    if (verboseLogging)
                    {
                        Console.WriteLine("{0} rows returned for iteration {1}", rowCount, monthIteration+1);
                    }

                    Console.WriteLine(); //add some whitespace
                }

            outputFile.Close();

            }
        }
    }
}
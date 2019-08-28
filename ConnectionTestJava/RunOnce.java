import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;


public class RunOnce {
    static final String JDBC_DRIVER = "com.microsoft.sqlserver.jdbc.SQLServerDriver";
    public static void main(String[] args) {
	// write your code here

    System.out.println(System.getProperty("java.version"));

    String DatabaseName=args[0];
    int iterations = Integer.parseInt(args[1]);
    Connection conn = null;
    Statement stmt = null;
    String connectionUrl = DatabaseName;

    double total_time = 0;

    for(int outer = 0; outer < iterations; outer++)
        {
            try {

                Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
    
                //Open a connection
                System.out.println("Connecting to a selected database...");
                long start_time = System.nanoTime();
                conn = DriverManager.getConnection(connectionUrl);
                System.out.println("Connected database successfully...");
    
                stmt = conn.createStatement();
                for(int i = 0; i < 1; i++) {
                    ResultSet rs2 = stmt.executeQuery("SELECT 1 as myid");
                    rs2.close();
                }
                long end_time = System.nanoTime();
                    stmt.close();
                double difference = (end_time - start_time) / 1e6;
                System.out.println("Time taken:" + difference);
                total_time += difference;
    
            } catch(SQLException se){
                //Handle errors for JDBC
                se.printStackTrace();
            }catch(Exception e){
                //Handle errors for Class.forName
                e.printStackTrace();
            }finally{
                //finally block used to close resources
                try{
                    if(stmt!=null)
                        conn.close();
                }catch(SQLException se){
                }// do nothing
                try{
                    if(conn!=null)
                        conn.close();
                }catch(SQLException se){
                    se.printStackTrace();
                }//end finally try
                }//end try
        }

    System.out.println(System.getProperty("java.version"));
    System.out.println(iterations + " iterations took a total of " + total_time);
    System.out.println("Goodbye!");
    }
}

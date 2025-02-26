class Program
{
    private static readonly object _lockObject = new object();
    private static int _sharedResource = 0;

    static void Main()
    {
        Thread[] threads = new Thread[10];

        for (int i = 0; i < threads.Length; i++)
        {
            threads[i] = new Thread(IncrementResource);
            threads[i].Name = $"Thread {i + 1}";
            threads[i].Start();
        }

        foreach (Thread thread in threads)
        {
            thread.Join();
        }

        Console.WriteLine($"Final value of shared resource: {_sharedResource}");
    }

    private static void IncrementResource()
    {
        for (int i = 0; i < 1000; i++)
        {
            lock (_lockObject)
            {
                Thread.Sleep(50);
                int temp = _sharedResource;
                temp++;
                _sharedResource = temp;
                Console.WriteLine($"{Thread.CurrentThread.Name} incremented value to {_sharedResource}");
            }
        }
    }
}

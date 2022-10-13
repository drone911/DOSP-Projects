# DOSP Project 1
By Anurag Chakraborty and Jigar Patel 

# How to execute

* Start the server with either:
	* `bitcoin:start_server()` and enter the requested details OR
	* `bitcoin:start_server("<YOUR_GATOR_ID_HERE>", <Number of Zeroes>).` 
* Start workers using `bitcoin:start_worker(<SERVER_NODE_NAME>).`
* I/O screenshots attached.

# Questions

**Q.1: Size of the work unit that you determined results in the best performance for your implementation and an explanation of how you determined it.**

Intitially, we started out with just 1000 work unit. This soon proved to be  inefficient and small value as the workers would have to request "work" quite frequently from the server and wait for the response, essentially creating a bottleneck.

Starting out from 1000, we first increased the work unit by a factor of 10, and noticed that 3 workers running concurrently were still requesting for work from the server fairly quickly, thus creating the same bottleneck as mentioned above.

Upon setting the work unit to 500000, we noticed that 3 workers running concurrently, there was significant reduction in the frequency in which the workers were requesting the next work unit from the server and consequently, there was a minute reduction in the runtime.

If we were to make the work unit larger than 500000, then, once a worker finds a coin, there would be unnecessary computations done by the remaining workers till they ask the server for next work and realize that the coin has already been found.

So, based on the above we settled on a work unit of 500000.

**Q.2: The result of running your program for input 4.**

the output received

``` 
Received coin "ji.patel3j" "0000c8bee8e5d9f1e2d0edffa2dae2783b15f5b2b1e55f52389c225efbb5ad28" From worker1@MSI
Node Runtime (in milliseconds): 16  
```

**Q.3: The running time for the above is reported by time for the above and report the time. The ratio of CPU time to REAL TIME**

On running with 3 workers (1 Server + 2 Workers), for input 
GatorId: "ji.patel" and NumZeroes: 5  

* The total  CPU runtime was 344,031 ms

* The real time was 113,506 ms

The **ratio of total CPU runtime to real time was 3.03**.

**Q.4 The coin with the most 0s you managed to find.**

The coin with most number of zeroes we were able to find is 8.

```
Received coin "ji.patel7i7i?" "00000000a4cc9e6ae51def43610d576df4c9258f01e5bd29797d25ad4bebca4f" From worker3@MSI
Time take to find the Coin (in milliseconds): 579536
```

**Q.5 The largest number of working machines you were able to run your code with.**

We ran the miner with 10 nodes across 2 separate machines to find a hash with 9 zeroes as prefix, but we could not find the coin. Nevertheless, it checked more than 2 billion combinations over span of 1 hour.
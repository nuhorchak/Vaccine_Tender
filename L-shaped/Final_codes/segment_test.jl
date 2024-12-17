            # Parameters
            segments = 5
            discount_rate = 0.05

            # Initialize segment boundaries
            segment_upper = Dict{Int, Float64}()
            segment_lower = Dict{Int, Float64}()

            # Populate segment boundaries
            for m in 1:segments
            segment_lower[m] = (1 - discount_rate)^(m - 1)
            segment_upper[m] = (1 - discount_rate)^m
            end

            # Print results
            println("Segment Boundaries:")
            for m in 1:segments
            println("Segment $m: Lower = $(segment_lower[m]), Upper = $(segment_upper[m])")
            end
import math
import numpy as np

if __name__ == '__main__':
    expectedAVG = 10.0
    expectedVAR = 0.0

    avg_mse = 0
    var_mse = 0
    gloval_avg = 0
    gloval_var = 0
    rounds = 0
    NaNs = 0
    perfect_avg = 0
    perfect_var = 0

    with open("logfile.txt") as f:
        for line in f:
            _, _, _, t1, t2 = line.strip().split()

            avg = float(t1)
            var = float(t2)
            if not (math.isnan(avg) or math.isnan(var)):
                print(rounds+1, ". ", avg, var)
                f_avg = float(avg)
                f_var = float(var)

                gloval_avg += f_avg
                gloval_var += f_var

                avg_mse += np.mean((f_avg - expectedAVG) ** 2)
                var_mse += np.mean((f_var - expectedVAR) ** 2)

                if avg == 10:
                    perfect_avg += 1
                if var == 0:
                    perfect_var += 1
            else:
                NaNs += 1

            # Next round
            rounds += 1

        normalized_avg = gloval_avg / rounds
        normalized_var = gloval_var / rounds
        avg_mse /= rounds
        var_mse /= rounds

        print("\n*******************\n")
        print("NaNs: ", NaNs)
        print("Rounds: ", rounds)

        print("AVG: ", "%.4f" % normalized_avg)
        print("VAR: ", "%.4f" % normalized_var)

        print("AVG_MSE: %.2f" % avg_mse)
        print("VAR_MSE: %.2f" % var_mse)

        print("Perfect AVG: ", perfect_avg, "/", rounds, "rounds |", "%.2f" % (100 * perfect_avg / rounds), "%")
        print("Perfect VAR: ", perfect_var, "/", rounds, "rounds |", "%.2f" % (100 * perfect_var / rounds), "%")

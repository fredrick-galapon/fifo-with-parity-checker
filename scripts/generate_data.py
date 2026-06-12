import numpy as np
import argparse


def generate_words(num_words: int, bit_width: int) -> list:
    """
    Generate a list of random words. 

    Parameters:
        num_words : int
            Number of words to generate. 
        bit_width : int
            Number of bits in each word. 

    Returns:
        list: List of NumPy arrays. 
    """

    return [np.random.randint(0, 2, size=bit_width) for _ in range(num_words)]


def compute_parity(bit_vector: np.ndarray, parity_type: str = "even", parity_bit="lsb") -> np.ndarray:
    """
    Compute the parity bit of a given bit vector. 

    Parameters:
        bit_vector : np.ndarray
            Bit vector to compute parity for. 
        parity_type : str
            Parity type, either "even" or "odd". 
        parity_bit : str
            Position of parity bit, either "lsb" or "msb". 

    Returns:
        np.ndarray: Bit vector with parity. 
    """
    
    parity = int(np.sum(bit_vector)) % 2
    if parity_type == "odd":
        parity = 1 - parity
    
    if parity_bit == "lsb":
        return np.append(bit_vector, parity)
    else:
        return np.insert(bit_vector, 0, parity)
    

def bin_to_hex(bit_vector: np.ndarray, bit_width: int) -> str:
    """
    Convert a given bit vector to its hex representation. 

    Parameters:
        bit_vector : np.ndarray
            Bit vector to convert. 
        bit_width : int
            Number of bits in vector. 

    Returns:
        str: Hex representation of bit vector. 
    """

    bin_str = ''.join(map(str, bit_vector))
    int_value = int(bin_str, 2)
    hex_width = int(np.ceil(bit_width / 4))

    return f"{int_value:0{hex_width}X}"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--num_words", type=int, default=32, help="Number of words to generate.")
    parser.add_argument("--bit_width", type=int, default=32, help="Number of bits in each word.")
    parser.add_argument("--parity_type", type=str, choices=["even", "odd"], default="even", help="Type of parity.")
    parser.add_argument("--parity_bit", type=str, choices=["lsb", "msb"], default="lsb", help="Position of parity bit.")
    args = parser.parse_args()

    words = generate_words(num_words=args.num_words, bit_width=args.bit_width)
    with open("../sim/data.txt", "w") as f:
        for word in words:
            full_word = compute_parity(bit_vector=word, 
                                       parity_type=args.parity_type, 
                                       parity_bit=args.parity_bit)
            hex_str = bin_to_hex(bit_vector=full_word, 
                                 bit_width=args.bit_width+1)    # +1 for parity bit
            f.write(hex_str + "\n")

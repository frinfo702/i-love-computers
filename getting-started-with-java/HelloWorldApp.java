import java.util.Scanner;

/**
The HelloWorldApp class implements an application that
simply displays "Hello World" to the standard output.
*/
public class HelloWorldApp {

    public static void main(String[] args) {
        System.out.println("Hola Mundo!");

        Scanner scanner = new Scanner(System.in, "UTF-8");
        System.out.println("What is your name?");

        String name = scanner.nextLine();
        scanner.close();

        System.out.println("Hello " + name);
    }
}
